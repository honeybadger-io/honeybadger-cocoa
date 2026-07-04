#import "HBTest.h"
#import "HoneybadgerTestAccess.h"
#include <signal.h>
#include <string.h>

// Chaining must hand a SA_SIGINFO predecessor the ORIGINAL siginfo_t/ucontext
// (fault address intact), not a synthetic re-raise. These tests exercise
// hb_chain_previous_signal directly — no real signal is delivered, so they
// are safe in-process. The SIG_DFL path (restore + re-raise) is covered by
// the integration harness, where the crash run genuinely terminates.

static volatile int chain_siginfo_calls = 0;
static void* chain_received_addr = NULL;
static void fake_siginfo_handler(int sig, siginfo_t* info, void* uap) {
    chain_siginfo_calls++;
    chain_received_addr = info ? info->si_addr : NULL;
}

static volatile int chain_plain_calls = 0;
static int chain_plain_signal = 0;
static void fake_plain_handler(int sig) {
    chain_plain_calls++;
    chain_plain_signal = sig;
}

static int index_of_signal(int sig) {
    for ( int i = 0; i < 6; i++ ) {   // HB_SIGNAL_COUNT is 6 (private to the SDK)
        if ( hb_signals[i] == sig ) return i;
    }
    return -1;
}

void run_signal_chain_tests(void)
{
    int idx = index_of_signal(SIGSEGV);
    HB_TEST_BEGIN("testSignalTableContainsSIGSEGV");
    HB_ASSERT_TRUE(idx >= 0);

    // Snapshot real state so these tests leave no trace.
    struct sigaction savedDisposition;
    sigaction(SIGSEGV, NULL, &savedDisposition);
    struct sigaction savedPrev = hb_previous_signal_actions[idx];

    HB_TEST_BEGIN("testChainInvokesSigInfoPredecessorWithOriginalInfo");
    struct sigaction fake;
    memset(&fake, 0, sizeof(fake));
    sigemptyset(&fake.sa_mask);
    fake.sa_sigaction = fake_siginfo_handler;
    fake.sa_flags = SA_SIGINFO;
    hb_previous_signal_actions[idx] = fake;

    siginfo_t info;
    memset(&info, 0, sizeof(info));
    info.si_signo = SIGSEGV;
    info.si_addr = (void*)0xDEADBEEF;

    chain_siginfo_calls = 0;
    chain_received_addr = NULL;
    hb_chain_previous_signal(SIGSEGV, &info, NULL);
    HB_ASSERT_EQ_INT(chain_siginfo_calls, 1);
    HB_ASSERT_TRUE(chain_received_addr == (void*)0xDEADBEEF);

    HB_TEST_BEGIN("testChainInvokesPlainPredecessor");
    memset(&fake, 0, sizeof(fake));
    sigemptyset(&fake.sa_mask);
    fake.sa_handler = fake_plain_handler;
    hb_previous_signal_actions[idx] = fake;

    chain_plain_calls = 0;
    hb_chain_previous_signal(SIGSEGV, &info, NULL);
    HB_ASSERT_EQ_INT(chain_plain_calls, 1);
    HB_ASSERT_EQ_INT(chain_plain_signal, SIGSEGV);

    HB_TEST_BEGIN("testChainIgnoresSigIgnPredecessor");
    memset(&fake, 0, sizeof(fake));
    sigemptyset(&fake.sa_mask);
    fake.sa_handler = SIG_IGN;
    hb_previous_signal_actions[idx] = fake;
    hb_chain_previous_signal(SIGSEGV, &info, NULL);
    // Reaching this line at all proves SIG_IGN neither crashed nor re-raised.
    HB_ASSERT_TRUE(1);

    // Restore everything.
    hb_previous_signal_actions[idx] = savedPrev;
    sigaction(SIGSEGV, &savedDisposition, NULL);

    HB_TEST_BEGIN("testLatchRearmsWhenProcessSurvivesSignal");
    // A SIG_IGN'd predecessor means hb_chain_previous_signal returns and the
    // process survives delivery. The one-shot entry latch must re-arm, or
    // every later real crash is chained past capture for the process's life.
    int latchIdx = -1;
    for ( int i = 0; i < 6; i++ ) {  // 6 == HB_SIGNAL_COUNT
        if ( hb_signals[i] == SIGSEGV ) latchIdx = i;
    }
    HB_ASSERT_TRUE(latchIdx >= 0);
    struct sigaction savedLatchPrev = hb_previous_signal_actions[latchIdx];
    struct sigaction ignoreAction;
    memset(&ignoreAction, 0, sizeof(ignoreAction));
    ignoreAction.sa_handler = SIG_IGN;
    hb_previous_signal_actions[latchIdx] = ignoreAction;

    hb_exception_captured = 0;
    hb_handler_entered = 0;
    siginfo_t latchInfo;
    memset(&latchInfo, 0, sizeof(latchInfo));
    hb_signal_handler(SIGSEGV, &latchInfo, NULL);  // capture path, then chain returns
    HB_ASSERT_EQ_INT((int)hb_handler_entered, 0);

    // The exception-captured early-out must also re-arm on survival.
    hb_exception_captured = 1;
    hb_signal_handler(SIGSEGV, &latchInfo, NULL);
    HB_ASSERT_EQ_INT((int)hb_handler_entered, 0);
    hb_exception_captured = 0;

    hb_previous_signal_actions[latchIdx] = savedLatchPrev;
}
