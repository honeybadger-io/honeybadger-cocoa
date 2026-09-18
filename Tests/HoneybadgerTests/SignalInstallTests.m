#import "HBTest.h"
#import "HoneybadgerTestAccess.h"
#include <signal.h>
#include <pthread.h>
#include <pthread/introspection.h>
#include <unistd.h>

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

// A forked child re-fires the introspection hook during libsystem's
// atfork-child re-init (_pthread_main_thread_postfork_init), where malloc and
// free are illegal. The hook must do nothing when the current pid no longer
// matches the pid that installed it. Runs on its own thread so altstack
// manipulation never touches the main thread's hb_signal_stack.
typedef struct {
    int hookSetThreadSpecificStack;
    int destructorDisablesAltStack;
    int startInertOnPidMismatch;
    int startInstallsOnMatch;
} hb_fork_guard_results;

static void* hb_fork_guard_probe(void* arg)
{
    hb_fork_guard_results* r = (hb_fork_guard_results*)arg;
    pid_t installPid = hb_hook_install_pid;
    stack_t st;

    // The real hook gave this thread an alt stack at creation and recorded
    // ownership in TSD; the TSD destructor must disable (and free) it.
    void* stackMem = pthread_getspecific(hb_thread_alt_stack_key);
    r->hookSetThreadSpecificStack = (stackMem != NULL);
    hb_thread_alt_stack_destructor(stackMem);
    pthread_setspecific(hb_thread_alt_stack_key, NULL);
    r->destructorDisablesAltStack = (sigaltstack(NULL, &st) == 0 && (st.ss_flags & SS_DISABLE));

    // Simulate the forked child: current pid differs from the installing pid.
    // START must not malloc or install anything.
    hb_hook_install_pid = installPid + 1;
    hb_thread_introspection_hook(PTHREAD_INTROSPECTION_THREAD_START, pthread_self(), NULL, 0);
    r->startInertOnPidMismatch = (sigaltstack(NULL, &st) == 0 && (st.ss_flags & SS_DISABLE));

    // Back in the installing process, START works normally again; the stack
    // it installs here is freed by the TSD destructor at thread exit.
    hb_hook_install_pid = installPid;
    hb_thread_introspection_hook(PTHREAD_INTROSPECTION_THREAD_START, pthread_self(), NULL, 0);
    r->startInstallsOnMatch = (sigaltstack(NULL, &st) == 0 && !(st.ss_flags & SS_DISABLE));

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

    HB_TEST_BEGIN("testIntrospectionHookInertInForkedChild");
    HB_ASSERT_EQ_INT(hb_hook_install_pid, getpid());
    hb_fork_guard_results results = { 0 };
    pthread_t forkGuardThread;
    HB_ASSERT_EQ_INT(pthread_create(&forkGuardThread, NULL, hb_fork_guard_probe, &results), 0);
    pthread_join(forkGuardThread, NULL);
    HB_ASSERT_TRUE(results.hookSetThreadSpecificStack);
    HB_ASSERT_TRUE(results.destructorDisablesAltStack);
    HB_ASSERT_TRUE(results.startInertOnPidMismatch);
    HB_ASSERT_TRUE(results.startInstallsOnMatch);
}
