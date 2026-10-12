*** Settings ***
Documentation    Suite 10: Pop-ups, loading and notices.
...    Tests that the level-up, achievement, notice and World Complete pop-ups
...    close by themselves after the right time and when clicked, that the first
...    load shows a loading indicator and the "Waking up the server" message,
...    that the first load retries by itself when the backend does not answer,
...    and that the main browser flows cause no console errors or Content
...    Security Policy violations.
...    How long a pop-up stays open is measured inside the page, from the moment
...    it appears to the moment it disappears, so the test's own speed (SLOWMO)
...    does not affect the result.
...    A slow or unavailable backend is simulated with the keywords from
...    resources/BrowserExtensions.js, which hold or fail the page's requests to
...    the backend before they leave the browser. The backend itself keeps
...    running.
...    Covers test cases TC10-001 - TC10-007.
...    Precondition: the .env test account exists in the app.
Resource    ../resources/common.robot
Suite Setup    Sign In For Pop-up Tests
Suite Teardown    Clean Up Suite
Test Teardown    Reset Player State    ${USER_ID}


*** Test Cases ***
Level-up pop-up closes by itself and on click
    [Documentation]    TC10-001. Expected result: the level-up pop-up closes by itself
    ...    after about 2.5 seconds. When it appears again (undo and complete the
    ...    task to cross the level again), clicking it closes it at once.
    [Tags]    browser
    ${today}=    Today Key
    ${walk}=    Catalog Mission    walk    ${today}    ${False}
    Seed Pop-up Player    @{EMPTY}    totalXp=${95}    missions=${{ [$walk] }}
    Reload Game
    Start Pop-up Timer    .levelup-overlay
    Click    .mission-check >> nth=0
    Pop-up Should Close By Itself    .levelup-overlay    2.5
    Click    .mission-check >> nth=0
    Wait For Elements State    .mission-check >> nth=0 >> text=☐    visible    timeout=5s
    Click    .mission-check >> nth=0
    Pop-up Should Close On Click    .levelup-overlay

Achievement pop-up shows its details and closes by itself and on click
    [Documentation]    TC10-002. Expected result: the achievement pop-up shows the
    ...    title, the description and the reward (First Step, "Complete your first
    ...    task", "+15 XP · 1 food") and closes by itself after about 3 seconds.
    ...    The next time an achievement is unlocked, clicking the pop-up closes it
    ...    at once.
    [Tags]    browser
    ${today}=    Today Key
    ${walk}=    Catalog Mission    walk    ${today}    ${False}
    Seed Pop-up Player    first_task    missions=${{ [$walk] }}
    Reload Game
    Start Pop-up Timer    .achievement
    Click    .mission-check >> nth=0
    Wait For Elements State    .achievement    visible    timeout=5s
    Get Text    .achievement-title    ==    First Step
    Get Text    .achievement-desc    ==    Complete your first task
    Get Text    .achievement-reward    ==    +15 XP · 1 food
    Pop-up Should Close By Itself    .achievement    3
    ${run}=    Catalog Mission    run    ${today}    ${False}
    Seed Pop-up Player    first_task    missions=${{ [$run] }}
    Reload Game
    Click    .mission-check >> nth=0
    Pop-up Should Close On Click    .achievement

Notice closes by itself and on click
    [Documentation]    TC10-003. Expected result: the notice (here the daily limit
    ...    notice, shown when a 31st task is completed on the same day) closes by
    ...    itself after about 3 seconds. Shown again, it closes at once when
    ...    clicked.
    [Tags]    browser
    ${today}=    Today Key
    ${missions}=    Evaluate
    ...    [{'id': 2000 + i, 'date': $today, 'key': 'quota' + str(i), 'name': 'Quota task ' + str(i), 'icon': '✔', 'xp': 1, 'resources': {}, 'done': i < 30} for i in range(31)]
    Seed Pop-up Player    @{EMPTY}    missions=${missions}
    Reload Game
    ${extra}=    Set Variable    css=.mission:has(.mission-name:text-is("✔ Quota task 30")) >> .mission-check
    Start Pop-up Timer    .notice
    Click    ${extra}
    Wait For Elements State    .notice    visible    timeout=5s
    Get Text    .notice-text    contains    Today's quota of 30 tasks is done
    Pop-up Should Close By Itself    .notice    3
    Click    ${extra}
    Pop-up Should Close On Click    .notice

World Complete closes by itself and on click
    [Documentation]    TC10-004. Expected result: World Complete closes by itself after
    ...    about 4 seconds (4.2 s). Shown again, it closes at once when clicked.
    [Tags]    browser
    FOR    ${how}    IN    by itself    on click
        Seed Pop-up Player    @{EMPTY}    totalXp=${400000}    baseStageIndex=${6}
        ...    resources=${{ {'wood': 5000, 'stone': 5000, 'food': 5000} }}
        Reload Game
        Start Pop-up Timer    .worldcomplete-overlay
        Click    .base-build-button
        IF    '${how}' == 'by itself'
            Pop-up Should Close By Itself    .worldcomplete-overlay    4.2
        ELSE
            Pop-up Should Close On Click    .worldcomplete-overlay
        END
    END

Loading indicator and waking-up message during a slow first load
    [Documentation]    TC10-005. Expected result: while the game state is loading, a
    ...    loading indicator is shown in place of the world. When the backend
    ...    answers slowly (here every game state request is held for 6 seconds),
    ...    the message "Waking up the server…" appears after a few seconds. When
    ...    the answer arrives, the indicator disappears and the game is shown.
    [Tags]    browser
    Simulate Slow Or Down Backend    ${BACKEND_URL}    delay
    Reload
    Wait For Elements State    .base-loading    visible    timeout=10s
    Get Element Count    .base-status    ==    0
    Wait For Elements State    .base-loading-message    visible    timeout=10s
    Get Text    .base-loading-message    contains    Waking up the server
    Wait For Game To Load
    Get Element Count    .base-loading    ==    0
    ${counts}=    Restore Backend    ${BACKEND_URL}
    Should Be True    ${counts}[held] >= 1    msg=No game state request was held, the slow backend was not simulated
    [Teardown]    Restore Backend And Reset

First load retries by itself when the backend does not answer
    [Documentation]    TC10-006. Expected result: when the backend does not answer the
    ...    first load (here the first two requests fail as if the server were
    ...    down), the app keeps retrying by itself and shows the game as soon as
    ...    the backend answers, without a manual reload. A marker set in the page
    ...    while it is still loading shows that the page was never reloaded.
    [Tags]    browser
    Simulate Slow Or Down Backend    ${BACKEND_URL}    fail
    Reload
    Wait For Elements State    .base-loading    visible    timeout=10s
    Evaluate JavaScript    ${None}    () => { window.__samePage = true; }
    Wait For Game To Load
    ${counts}=    Restore Backend    ${BACKEND_URL}
    Should Be Equal As Integers    ${counts}[failed]    2    msg=The simulated outage did not happen as planned
    ${same_page}=    Evaluate JavaScript    ${None}    () => window.__samePage === true
    Should Be True    ${same_page}    msg=The page was reloaded instead of retrying
    [Teardown]    Restore Backend And Reset

Main browser flows cause no console errors or CSP violations
    [Documentation]    TC10-007. Expected result: in a fresh browser session, signing
    ...    in, loading the game, adding, completing and undoing a task, moving
    ...    between days, opening and closing the companion and building cause no
    ...    console errors, no uncaught page errors and no Content Security Policy
    ...    violations. Warnings (for example Clerk's development keys warning) are
    ...    not errors.
    [Tags]    browser    security
    ${main}=    Get Context Ids    ACTIVE    ACTIVE
    Seed Pop-up Player    @{EMPTY}    totalXp=${100}    resources=${{ {'wood': 50, 'stone': 50, 'food': 50} }}
    Open New Session
    TRY
        Start CSP Watcher
        Sign In
        Start CSP Watcher
        Click    .add-task-button
        Wait For Elements State    .add-task-modal    visible    timeout=5s
        Click    .add-task-option >> nth=0
        Click    .add-task-done
        Wait For Elements State    .add-task-modal    detached    timeout=5s
        Click    .mission-check >> nth=0
        Wait For Elements State    .mission-check >> nth=0 >> text=☑    visible    timeout=5s
        Click    .mission-check >> nth=0
        Wait For Elements State    .mission-check >> nth=0 >> text=☐    visible    timeout=5s
        Click    .day-nav-arrow[aria-label="Previous day"]
        Click    .day-nav-arrow[aria-label="Next day"]
        Evaluate JavaScript    ${None}    () => sessionStorage.setItem('nimeoniter_greeted', '1')
        Click    .assistant__figure
        Wait For Elements State    .assistant__backdrop    visible    timeout=5s
        Click    .assistant__figure
        Wait For Elements State    .assistant__backdrop    detached    timeout=5s
        Click    .base-build-button
        Get Text    .base-world-stage    ==    WELL
        Sleep    1s
        No Errors Should Have Happened
    FINALLY
        Close Context
        Switch Context    ${main}[0]
    END


*** Keywords ***
Sign In For Pop-up Tests
    [Documentation]    Signs the standard test account in.
    Open Test Browser
    Open New Session
    Sign In
    ${user_id}=    Get Current User Id
    Set Suite Variable    ${USER_ID}    ${user_id}
    ${config}=    GET    ${BACKEND_URL}/api/config
    ${ids}=    Evaluate    [a['id'] for a in $config.json()['achievements']]
    Set Suite Variable    ${ALL_ACHIEVEMENTS}    ${ids}

Clean Up Suite
    [Documentation]    Resets the test account's game state and closes the browser.
    Run Keyword And Ignore Error    Reset Player State    ${USER_ID}
    Close Browser

Seed Pop-up Player
    [Documentation]    Seeds the test player with the given fields. The listed
    ...    achievement ids stay locked; every other achievement starts as already
    ...    unlocked, so only the pop-ups under test appear. Use @{EMPTY} to unlock
    ...    everything.
    [Arguments]    @{locked}    &{fields}
    ${unlocked}=    Evaluate    [a for a in $ALL_ACHIEVEMENTS if a not in $locked]
    Seed Player State    ${USER_ID}    unlockedAchievements=${unlocked}    &{fields}

Catalog Mission
    [Documentation]    Returns a task entry for a catalog task on the given day, in the
    ...    shape the backend stores, with a unique id.
    [Arguments]    ${key}    ${date}    ${done}
    ${task}=    Catalog Task    ${key}
    ${id}=    Evaluate    random.randint(10**9, 10**10)    modules=random
    ${mission}=    Evaluate
    ...    {'id': $id, 'date': $date, 'key': $task['key'], 'name': $task['name'], 'icon': $task['icon'], 'xp': $task['xp'], 'resources': $task['resources'], 'done': $done}
    RETURN    ${mission}

Start Pop-up Timer
    [Documentation]    Starts a watcher in the page that records, in milliseconds, when
    ...    an element matching the selector appears and when it disappears again.
    [Arguments]    ${selector}
    Evaluate JavaScript    ${None}
    ...    (selector) => {
    ...        const timer = { shown: null, hidden: null };
    ...        window.__popupTimer = timer;
    ...        new MutationObserver(() => {
    ...            const present = !!document.querySelector(selector);
    ...            if (present && timer.shown === null) timer.shown = performance.now();
    ...            if (!present && timer.shown !== null && timer.hidden === null) timer.hidden = performance.now();
    ...        }).observe(document, { childList: true, subtree: true });
    ...    }
    ...    arg=${selector}

Pop-up Should Close By Itself
    [Documentation]    Waits until the pop-up has appeared and closed by itself, and
    ...    checks that it stayed open for the expected number of seconds (from
    ...    0.3 s less to 0.7 s more, to allow for the browser's own timing).
    [Arguments]    ${selector}    ${seconds}
    Wait For Elements State    ${selector}    visible    timeout=5s
    ${limit}=    Evaluate    float($seconds) + 5
    Wait For Elements State    ${selector}    detached    timeout=${limit}s
    ${open_for}=    Evaluate JavaScript    ${None}
    ...    () => (window.__popupTimer.hidden - window.__popupTimer.shown) / 1000
    ${low}=    Evaluate    float($seconds) - 0.3
    ${high}=    Evaluate    float($seconds) + 0.7
    Should Be True    ${low} <= ${open_for} <= ${high}
    ...    msg=The pop-up stayed open ${open_for} s, expected about ${seconds} s

Pop-up Should Close On Click
    [Documentation]    Waits until the pop-up appears, clicks it and checks that it
    ...    closes at once (well before it would close by itself).
    [Arguments]    ${selector}
    Wait For Elements State    ${selector}    visible    timeout=5s
    Click    ${selector}
    Wait For Elements State    ${selector}    detached    timeout=1s
    ...    message=The pop-up did not close when it was clicked

Restore Backend And Reset
    [Documentation]    Teardown for the slow and down backend tests: removes the
    ...    simulation even if the test failed, and resets the game state.
    Run Keyword And Ignore Error    Restore Backend    ${BACKEND_URL}
    Reset Player State    ${USER_ID}

Start CSP Watcher
    [Documentation]    Records every Content Security Policy violation reported in the
    ...    page. Started again after sign-in in case the page was replaced.
    Evaluate JavaScript    ${None}
    ...    () => {
    ...        if (window.__cspViolations) return;
    ...        window.__cspViolations = [];
    ...        document.addEventListener('securitypolicyviolation', (e) => {
    ...            window.__cspViolations.push(e.violatedDirective + ' ' + e.blockedURI);
    ...        });
    ...    }

No Errors Should Have Happened
    [Documentation]    Checks the whole console log of the session for errors
    ...    (CSP violations are also reported there as errors), the uncaught page
    ...    errors and the CSP violations recorded in the page.
    ${log}=    Get Console Log    full=True
    ${errors}=    Evaluate    [m['text'] for m in $log if m['type'] == 'error']
    ${page_errors}=    Get Page Errors    full=True
    ${csp}=    Evaluate JavaScript    ${None}    () => window.__cspViolations || []
    Run Keyword And Continue On Failure    Should Be Empty    ${errors}    msg=Console errors: ${errors}
    Run Keyword And Continue On Failure    Should Be Empty    ${page_errors}    msg=Page errors: ${page_errors}
    Run Keyword And Continue On Failure    Should Be Empty    ${csp}    msg=CSP violations: ${csp}