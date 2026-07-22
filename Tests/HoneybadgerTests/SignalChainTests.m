#import "HBTest.h"
#import "HoneybadgerTestAccess.h"
#include <signal.h>
#include <string.h>
#include <sys/ucontext.h>

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

    HB_TEST_BEGIN("testInterruptedProgramCounterUsesMachineContext");
    ucontext_t context;
    memset(&context, 0, sizeof(context));
    _STRUCT_MCONTEXT machineContext;
    memset(&machineContext, 0, sizeof(machineContext));
    context.uc_mcontext = &machineContext;
    context.uc_mcsize = sizeof(machineContext);
#if defined(__arm64__)
    machineContext.__ss.__pc = 0x100001234ULL;
#elif defined(__x86_64__)
    machineContext.__ss.__rip = 0x100001234ULL;
#endif
    uint64_t programCounter = 0;
    HB_ASSERT_TRUE(hb_interrupted_program_counter(&context, &programCounter));
    HB_ASSERT_EQ_INT((long long)programCounter, 0x100001234ULL);

    HB_TEST_BEGIN("testInterruptedProgramCounterRejectsUnavailableContext");
    HB_ASSERT_TRUE(!hb_interrupted_program_counter(NULL, &programCounter));
    context.uc_mcontext = NULL;
    HB_ASSERT_TRUE(!hb_interrupted_program_counter(&context, &programCounter));
    context.uc_mcontext = &machineContext;
    context.uc_mcsize = sizeof(machineContext) - 1;
    HB_ASSERT_TRUE(!hb_interrupted_program_counter(&context, &programCounter));

    HB_TEST_BEGIN("testSignalAddressesPrependExactInterruptedPC");
    context.uc_mcsize = sizeof(machineContext);
    void* unwound[] = { (void*)0x10, (void*)0x20, (void*)0x100002000, (void*)0x100003000 };
    uint64_t crashAddresses[4] = {0};
    int32_t firstFrameIsReturnAddress = -1;
    int crashAddressCount = hb_build_signal_addresses(
        &context, unwound, 4, crashAddresses, 4, &firstFrameIsReturnAddress
    );
    HB_ASSERT_EQ_INT(crashAddressCount, 3);
    HB_ASSERT_EQ_INT((long long)crashAddresses[0], 0x100001234ULL);
    HB_ASSERT_EQ_INT((long long)crashAddresses[1], 0x100002000ULL);
    HB_ASSERT_EQ_INT((long long)crashAddresses[2], 0x100003000ULL);
    HB_ASSERT_EQ_INT(firstFrameIsReturnAddress, 0);

    HB_TEST_BEGIN("testZeroInterruptedPCRemainsAnExactFrame");
#if defined(__arm64__)
    machineContext.__ss.__pc = 0;
#elif defined(__x86_64__)
    machineContext.__ss.__rip = 0;
#endif
    firstFrameIsReturnAddress = -1;
    crashAddressCount = hb_build_signal_addresses(
        &context, NULL, 0, crashAddresses, 4, &firstFrameIsReturnAddress
    );
    HB_ASSERT_EQ_INT(crashAddressCount, 1);
    HB_ASSERT_EQ_INT((long long)crashAddresses[0], 0);
    HB_ASSERT_EQ_INT(firstFrameIsReturnAddress, 0);

    HB_TEST_BEGIN("testSignalAddressesMarkFallbackStackAsReturnAddresses");
    memset(crashAddresses, 0, sizeof(crashAddresses));
    firstFrameIsReturnAddress = 0;
    crashAddressCount = hb_build_signal_addresses(
        NULL, unwound, 4, crashAddresses, 4, &firstFrameIsReturnAddress
    );
    HB_ASSERT_EQ_INT(crashAddressCount, 2);
    HB_ASSERT_EQ_INT((long long)crashAddresses[0], 0x100002000ULL);
    HB_ASSERT_EQ_INT((long long)crashAddresses[1], 0x100003000ULL);
    HB_ASSERT_EQ_INT(firstFrameIsReturnAddress, 1);

    HB_TEST_BEGIN("testSignalAddressesDiscardPartialInternalUnwind");
    firstFrameIsReturnAddress = 0;
    crashAddressCount = hb_build_signal_addresses(
        NULL, unwound, 1, crashAddresses, 4, &firstFrameIsReturnAddress
    );
    HB_ASSERT_EQ_INT(crashAddressCount, 0);
    HB_ASSERT_EQ_INT(firstFrameIsReturnAddress, 1);

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
    // hb_chain_previous_signal installs the fake predecessor as SIGSEGV's live
    // disposition before invoking it; snapshot the real one so we can restore
    // it once this block is done chaining (twice) through the fake.
    struct sigaction savedLatchDisposition;
    sigaction(SIGSEGV, NULL, &savedLatchDisposition);
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
    sigaction(SIGSEGV, &savedLatchDisposition, NULL);
}
