#import "HBTest.h"
#import "HoneybadgerTestAccess.h"
#include <signal.h>
#include <pthread.h>

static void* hb_altstack_probe(void* arg)
{
    // Runs on a brand-new pthread. If the introspection hook installed an
    // alternate stack for this thread, sigaltstack reports it enabled.
    stack_t st;
    int* ok = (int*)arg;
    *ok = (sigaltstack(NULL, &st) == 0
           && !(st.ss_flags & SS_DISABLE)
           && st.ss_size >= (size_t)MINSIGSTKSZ);
    return NULL;
}

void run_signal_install_tests(void)
{
    HB_TEST_BEGIN("testHandlersInstalledWithAltStack");

    // Snapshot current dispositions so the test can restore them — leaving
    // Honeybadger handlers installed would poison other tests' crash behavior,
    // and a second install would capture our own handler as "previous".
    int signals[] = { SIGABRT, SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGTRAP };
    struct sigaction saved[6];
    for ( int i = 0; i < 6; i++ ) { sigaction(signals[i], NULL, &saved[i]); }

    [[Honeybadger sharedInstance] installSignalHandlers];

    struct sigaction current;
    sigaction(SIGSEGV, NULL, &current);
    HB_ASSERT_TRUE(current.sa_flags & SA_ONSTACK);
    HB_ASSERT_TRUE(current.sa_flags & SA_SIGINFO);

    stack_t ss;
    HB_ASSERT_EQ_INT(sigaltstack(NULL, &ss), 0);
    HB_ASSERT_FALSE(ss.ss_flags & SS_DISABLE);
    HB_ASSERT_TRUE(ss.ss_size >= (size_t)MINSIGSTKSZ);

    for ( int i = 0; i < 6; i++ ) { sigaction(signals[i], &saved[i], NULL); }

    HB_TEST_BEGIN("testNewThreadsGetAlternateSignalStack");
    int altStackOK = 0;
    pthread_t probeThread;
    HB_ASSERT_EQ_INT(pthread_create(&probeThread, NULL, hb_altstack_probe, &altStackOK), 0);
    pthread_join(probeThread, NULL);
    HB_ASSERT_TRUE(altStackOK);
}
