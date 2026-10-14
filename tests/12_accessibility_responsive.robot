*** Settings ***
Documentation    Suite 12: Accessibility, responsiveness and browsers.
...    Tests keyboard use, accessible names, text alternatives, the phone
...    layouts (portrait notice and landscape two-column layout), the tablet and
...    desktop widths, and reduced motion. Only the app's own elements are
...    checked for keyboard focus; Clerk's sign-in and account windows are a
...    third-party component.
...    TC12-011 (the browser suite on Chromium, Firefox and WebKit) is not a
...    separate test: the browser tests of every suite are run again with the
...    BROWSER value changed, for example in PowerShell:
...    $env:BROWSER="firefox"; python -m robot --include browser --outputdir results/firefox tests
...    Covers test cases TC12-001 - TC12-010. TC12-012 - TC12-015 are manual.
...    Precondition: the .env test account exists in the app.
Resource    ../resources/common.robot
Suite Setup    Sign In For Accessibility Tests
Suite Teardown    Clean Up Suite
Test Setup    Start From Desktop View
Test Teardown    Reset Player State    ${USER_ID}


*** Variables ***
@{ICON_BUTTONS}    Remove task    Previous day    Next day    Close    Send question    Talk to your companion


*** Test Cases ***
Every button can be reached and used with the keyboard
    [Documentation]    TC12-001. Expected result: pressing Tab moves through every
    ...    visible button of the game view, each focused button shows a visible
    ...    focus indicator, and a focused button can be activated with Enter and
    ...    with Space (here the day buttons: Next day with Enter shows TOMORROW,
    ...    Previous day with Space shows TODAY again).
    [Tags]    browser
    ${buttons}=    Evaluate JavaScript    ${None}
    ...    () => [...document.querySelectorAll('button')].filter((b) => !b.closest('[class*="cl-"]') && b.offsetParent !== null && !b.disabled).length
    ${reached}=    Tab Through Page    ${{ int($buttons) * 3 + 20 }}
    Run Keyword And Continue On Failure    Should Be Equal As Integers    ${reached}[buttons]    ${buttons}
    ...    msg=Tab reached ${reached}[buttons] of ${buttons} buttons. Not reached: ${reached}[missing]
    Run Keyword And Continue On Failure    Should Be Empty    ${reached}[no_focus_style]
    ...    msg=Buttons without a visible focus indicator: ${reached}[no_focus_style]
    Focus    .day-nav-arrow[aria-label="Next day"]
    Keyboard Key    press    Enter
    Get Text    .day-nav-label    ==    TOMORROW
    Focus    .day-nav-arrow[aria-label="Previous day"]
    Keyboard Key    press    Space
    Get Text    .day-nav-label    ==    TODAY

A task can be completed and undone with the keyboard
    [Documentation]    TC12-002. Expected result: the task's checkbox can be reached
    ...    with Tab, and Enter or Space completes the task and undoes it again.
    [Tags]    browser
    ${today}=    Today Key
    ${walk}=    Evaluate
    ...    {'id': 1001, 'date': $today, 'key': 'walk', 'name': 'Go for a walk', 'icon': '🚶', 'xp': 10, 'resources': {'wood': 2}, 'done': False}
    Seed Accessible Player    missions=${{ [$walk] }}
    Reload Game
    ${focusable}=    Evaluate JavaScript    .mission-check >> nth=0
    ...    (el) => el.tabIndex >= 0 || ['BUTTON', 'INPUT'].includes(el.tagName)
    Should Be True    ${focusable}    msg=The task checkbox cannot be reached with the keyboard (it is not a button and has no tabindex)
    Focus    .mission-check >> nth=0
    Keyboard Key    press    Enter
    Wait For Elements State    .mission-check >> nth=0 >> text=☑    visible    timeout=5s
    Keyboard Key    press    Space
    Wait For Elements State    .mission-check >> nth=0 >> text=☐    visible    timeout=5s

Task picker and companion work with the keyboard
    [Documentation]    TC12-001. Expected result: a task can be chosen in the task
    ...    picker with Tab and Enter, and Escape closes the picker and returns
    ...    focus to the "+ Add task" button. The companion opens with Enter,
    ...    Escape closes it, and focus returns to the companion button. The
    ...    player is first marked as already greeted, so opening the companion
    ...    makes no OpenAI call.
    [Tags]    browser
    Seed Accessible Player
    Reload Game
    Evaluate JavaScript    ${None}    () => sessionStorage.setItem('nimeoniter_greeted', '1')
    Focus    .add-task-button
    Keyboard Key    press    Enter
    Wait For Elements State    .add-task-modal    visible    timeout=5s
    Keyboard Key    press    Tab
    ${on_task}=    Evaluate JavaScript    ${None}
    ...    () => document.activeElement.classList.contains('add-task-option-button')
    Should Be True    ${on_task}    msg=Tab from the search field did not reach the first task
    ${name}=    Evaluate JavaScript    ${None}
    ...    () => document.activeElement.querySelector('.add-task-option-name').textContent
    Keyboard Key    press    Enter
    Wait For Elements State    .mission-name >> text=${name}    visible    timeout=5s
    Keyboard Key    press    Escape
    Wait For Elements State    .add-task-modal    detached    timeout=5s
    ${on_add}=    Evaluate JavaScript    ${None}
    ...    () => document.activeElement.classList.contains('add-task-button')
    Should Be True    ${on_add}    msg=Focus did not return to the "+ Add task" button
    Focus    .assistant__figure
    Keyboard Key    press    Enter
    Wait For Elements State    .assistant__chat    visible    timeout=5s
    Keyboard Key    press    Escape
    Wait For Elements State    .assistant__chat    detached    timeout=5s
    ${on_figure}=    Evaluate JavaScript    ${None}
    ...    () => document.activeElement.classList.contains('assistant__figure')
    Should Be True    ${on_figure}    msg=Focus did not return to the companion button

Icon-only buttons have accessible names
    [Documentation]    TC12-003. Expected result: the buttons that show only an icon
    ...    have accessible names: Remove task, Previous day, Next day, Close (task
    ...    picker), Send question and Talk to your companion.
    [Tags]    browser
    ${today}=    Today Key
    ${walk}=    Evaluate
    ...    {'id': 1001, 'date': $today, 'key': 'walk', 'name': 'Go for a walk', 'icon': '🚶', 'xp': 10, 'resources': {'wood': 2}, 'done': False}
    Seed Accessible Player    missions=${{ [$walk] }}
    Reload Game
    Click    .add-task-button
    Wait For Elements State    .add-task-modal    visible    timeout=5s
    Run Keyword And Continue On Failure    Get Element Count    button[aria-label="Close"]    >=    1
    ...    message=The task picker's close button has no accessible name
    Click    .add-task-done
    Evaluate JavaScript    ${None}    () => sessionStorage.setItem('nimeoniter_greeted', '1')
    Click    .assistant__figure
    Wait For Elements State    .assistant__backdrop    visible    timeout=5s
    FOR    ${name}    IN    @{ICON_BUTTONS}
        IF    '${name}' == 'Close'    CONTINUE
        Run Keyword And Continue On Failure    Get Element Count    button[aria-label="${name}"]    >=    1
        ...    message=No button with the accessible name "${name}"
    END
    Click    .assistant__figure

Images have text alternatives and decorative graphics are hidden
    [Documentation]    TC12-004. Expected result: every image has a text alternative
    ...    (the landing page picture included), and every graphic is either
    ...    hidden from screen readers (aria-hidden) or has a role and a name of
    ...    its own. Checked on the landing page and in the game view.
    [Tags]    browser
    Run Keyword And Continue On Failure    Graphics Should Be Accessible    game view
    ${main}=    Get Context Ids    ACTIVE    ACTIVE
    Open New Session
    TRY
        Wait For Elements State    ${LANDING_BUTTON}    visible    timeout=15s
        Get Attribute    .landing-image    alt    ==    A lone survivor by a campfire in the dark
        Graphics Should Be Accessible    landing page
    FINALLY
        Close Context
        Switch Context    ${main}[0]
    END

Phone in portrait shows the rotate notice and landscape shows the game
    [Documentation]    TC12-005. Expected result: a phone held upright (375×667) shows
    ...    the "Turn your device sideways." notice with the companion. Turned
    ...    sideways (667×375) the notice disappears and the game is shown.
    [Tags]    browser
    Set Viewport Size    375    667
    Wait For Elements State    .rotate-notice    visible    timeout=5s
    Get Text    .rotate-notice-title    ==    Turn your device sideways.
    Get Element Count    .rotate-notice svg.face    ==    1
    Set Viewport Size    667    375
    Wait For Elements State    .rotate-notice    detached    timeout=5s
    Wait For Elements State    ${GAME_LOADED}    visible    timeout=5s

Phone in landscape shows two columns without vertical scrolling
    [Documentation]    TC12-006. Expected result: on a phone held sideways (667×375
    ...    and 844×390) the tasks and the world are side by side in two columns,
    ...    and the page does not scroll vertically.
    [Tags]    browser
    FOR    ${width}    ${height}    IN    667    375    844    390
        Set Viewport Size    ${width}    ${height}
        Sleep    0.5s
        ${layout}=    Get Layout
        Run Keyword And Continue On Failure    Should Be True    ${layout}[side_by_side]
        ...    msg=${width}×${height}: the columns are not side by side: ${layout}
        Run Keyword And Continue On Failure    Should Be True    ${layout}[page_height] <= ${height} + 1
        ...    msg=${width}×${height}: the page scrolls vertically (${layout}[page_height] px)
    END

Task picker in landscape shows several tasks and the Done button
    [Documentation]    TC12-007. Expected result: on a phone held sideways (667×375)
    ...    the task picker shows at least three tasks at once and its Done button
    ...    is fully visible on the screen.
    [Tags]    browser
    Set Viewport Size    667    375
    Click    .add-task-button
    Wait For Elements State    .add-task-modal    visible    timeout=5s
    ${visible}=    Evaluate JavaScript    ${None}
    ...    () => [...document.querySelectorAll('.add-task-option')].filter((o) => { const r = o.getBoundingClientRect(); const list = o.parentElement.getBoundingClientRect(); return r.height > 0 && r.top >= Math.max(0, list.top) - 1 && r.bottom <= Math.min(innerHeight, list.bottom) + 1; }).length
    Run Keyword And Continue On Failure    Should Be True    ${visible} >= 3    msg=Only ${visible} tasks are visible at once
    ${done}=    Get BoundingBox    .add-task-done
    Run Keyword And Continue On Failure    Should Be True    ${done}[y] >= 0 and ${done}[y] + ${done}[height] <= 375
    ...    msg=The Done button is not fully visible: ${done}
    Click    .add-task-done

Clerk windows fit inside the landscape screen
    [Documentation]    TC12-008. Expected result: on a phone held sideways (667×375)
    ...    Clerk's sign-in window and the Manage account window fit inside the
    ...    screen (the window itself may scroll inside, but it does not reach
    ...    outside the screen). The sign-in window is checked in a signed-out
    ...    session. The Manage account window is checked in a session restored
    ...    from the saved sign-in, so no new sign-in (and no email code) is needed.
    [Tags]    browser
    ${main}=    Get Context Ids    ACTIVE    ACTIVE
    Open New Session    667    375
    TRY
        Open Sign In
        Run Keyword And Continue On Failure    Window Should Fit    sign-in window    667    375
    FINALLY
        Close Context
        Switch Context    ${main}[0]
    END
    New Context    viewport={'width': 667, 'height': 375}    storageState=${SIGNED_IN_STATE}
    TRY
        New Page    ${APP_URL}
        Wait For Game To Load
        Open Profile Window
        Run Keyword And Continue On Failure    Window Should Fit    Manage account window    667    375
    FINALLY
        Close Context
        Switch Context    ${main}[0]
    END

Tablet and desktop widths have no horizontal scrolling
    [Documentation]    TC12-009. Expected result: at 768, 1024 and 1440 px wide the
    ...    page does not scroll sideways, and the key elements are visible: level,
    ...    tasks, Add task, resources, the world, the build button and the
    ...    companion.
    [Tags]    browser
    FOR    ${width}    IN    768    1024    1440
        Set Viewport Size    ${width}    900
        Sleep    0.5s
        ${page_width}=    Evaluate JavaScript    ${None}    () => document.documentElement.scrollWidth
        Run Keyword And Continue On Failure    Should Be True    ${page_width} <= ${width}
        ...    msg=${width} px: the page scrolls sideways (${page_width} px wide)
        FOR    ${element}    IN    .header-level-number    .mission-list    .add-task-button    .resource-bar
        ...    .base-world-svg    .base-build-button    .assistant__figure
            Run Keyword And Continue On Failure    Wait For Elements State    ${element}    visible    timeout=2s
            ...    message=${width} px: ${element} is not visible
        END
    END

Animations are switched off when reduced motion is preferred
    [Documentation]    TC12-010. Expected result: when the browser reports that the
    ...    user prefers reduced motion, the companion's breathing and the city's
    ...    neon signs do not animate. Without that preference they do.
    [Tags]    browser
    Seed Accessible Player    totalXp=${400000}    baseStageIndex=${10}
    ${main}=    Get Context Ids    ACTIVE    ACTIVE
    FOR    ${preference}    ${animated}    IN    no_preference    ${True}    reduce    ${False}
        New Context    viewport={'width': 1280, 'height': 900}    storageState=${SIGNED_IN_STATE}
        ...    reducedMotion=${preference}
        TRY
            New Page    ${APP_URL}
            Wait For Game To Load
            Wait For Elements State    .assistant__figure .face__breathe    attached    timeout=10s
            FOR    ${element}    IN    .assistant__figure .face__breathe    .base-world-svg .neon-pulse
                ${name}=    Evaluate JavaScript    ${element} >> nth=0    (el) => getComputedStyle(el).animationName
                Run Keyword And Continue On Failure    Should Be Equal    ${{ $name != 'none' }}    ${animated}
                ...    msg=${element} with ${preference}: animation "${name}"
            END
        FINALLY
            Close Context
            Switch Context    ${main}[0]
        END
    END


*** Keywords ***
Sign In For Accessibility Tests
    [Documentation]    Signs the standard test account in and saves the signed-in
    ...    session (under browser/, which git ignores) for the reduced motion test.
    Open Test Browser
    Open New Session
    Sign In
    ${user_id}=    Get Current User Id
    Set Suite Variable    ${USER_ID}    ${user_id}
    ${state}=    Save Storage State
    Set Suite Variable    ${SIGNED_IN_STATE}    ${state}
    ${config}=    GET    ${BACKEND_URL}/api/config
    ${ids}=    Evaluate    [a['id'] for a in $config.json()['achievements']]
    Set Suite Variable    ${ALL_ACHIEVEMENTS}    ${ids}

Clean Up Suite
    [Documentation]    Resets the test account's game state and closes the browser.
    Run Keyword And Ignore Error    Reset Player State    ${USER_ID}
    Close Browser

Seed Accessible Player
    [Documentation]    Seeds the test player with the given fields and every
    ...    achievement unlocked, so no pop-up gets in the way.
    [Arguments]    &{fields}
    Seed Player State    ${USER_ID}    unlockedAchievements=${ALL_ACHIEVEMENTS}    &{fields}

Start From Desktop View
    [Documentation]    Test setup: a fresh player with one task in the desktop size.
    ${today}=    Today Key
    ${walk}=    Evaluate
    ...    {'id': 1001, 'date': $today, 'key': 'walk', 'name': 'Go for a walk', 'icon': '🚶', 'xp': 10, 'resources': {'wood': 2}, 'done': False}
    Seed Accessible Player    missions=${{ [$walk] }}
    Set Viewport Size    1280    900
    Reload Game

Tab Through Page
    [Documentation]    Presses Tab the given number of times from the top of the page
    ...    and returns how many different visible buttons of the app got focus,
    ...    which buttons were never reached, and which focused buttons showed no
    ...    focus indicator (no outline and no box shadow).
    [Arguments]    ${presses}
    Evaluate JavaScript    ${None}    () => { document.activeElement && document.activeElement.blur(); window.scrollTo(0, 0); }
    Evaluate JavaScript    ${None}
    ...    () => {
    ...        window.__tabbed = { reached: new Set(), noStyle: new Set() };
    ...        document.addEventListener('focusin', (e) => {
    ...            const el = e.target;
    ...            if (el.tagName !== 'BUTTON' || el.closest('[class*="cl-"]')) return;
    ...            const name = el.getAttribute('aria-label') || el.textContent.trim() || el.className;
    ...            window.__tabbed.reached.add(el);
    ...            setTimeout(() => {
    ...                const s = getComputedStyle(el);
    ...                const outline = s.outlineStyle !== 'none' && parseFloat(s.outlineWidth) > 0;
    ...                if (!outline && s.boxShadow === 'none') window.__tabbed.noStyle.add(name);
    ...            }, 50);
    ...        });
    ...    }
    FOR    ${i}    IN RANGE    ${presses}
        Keyboard Key    press    Tab
    END
    Sleep    0.3s
    ${result}=    Evaluate JavaScript    ${None}
    ...    () => {
    ...        const all = [...document.querySelectorAll('button')].filter((b) => !b.closest('[class*="cl-"]') && b.offsetParent !== null && !b.disabled);
    ...        const name = (b) => b.getAttribute('aria-label') || b.textContent.trim() || b.className;
    ...        return {
    ...            buttons: all.filter((b) => window.__tabbed.reached.has(b)).length,
    ...            missing: all.filter((b) => !window.__tabbed.reached.has(b)).map(name),
    ...            no_focus_style: [...window.__tabbed.noStyle],
    ...        };
    ...    }
    RETURN    ${result}

Graphics Should Be Accessible
    [Documentation]    Checks that every image has a non-empty alt text and every
    ...    graphic (svg) is either hidden from screen readers or has role="img"
    ...    and a name. Graphics inside a hidden element, or inside a button or
    ...    link that has its own accessible name, are left out.
    [Arguments]    ${where}
    ${problems}=    Evaluate JavaScript    ${None}
    ...    () => {
    ...        const problems = [];
    ...        document.querySelectorAll('img').forEach((img) => {
    ...            if (!img.getAttribute('alt')) problems.push('img ' + img.getAttribute('src'));
    ...        });
    ...        document.querySelectorAll('svg').forEach((svg) => {
    ...            if (svg.parentElement.closest('svg, [aria-hidden="true"]')) return;
    ...            if (svg.parentElement.closest('button[aria-label], a[aria-label]')) return;
    ...            if (svg.getAttribute('aria-hidden') === 'true') return;
    ...            const named = svg.getAttribute('aria-label') || svg.getAttribute('aria-labelledby') || svg.querySelector(':scope > title');
    ...            if (svg.getAttribute('role') === 'img' && named) return;
    ...            problems.push('svg.' + (svg.getAttribute('class') || '(no class)'));
    ...        });
    ...        return problems;
    ...    }
    Should Be Empty    ${problems}    msg=${where}: graphics without a text alternative or aria-hidden: ${problems}

Get Layout
    [Documentation]    Returns whether the task column and the world column are side
    ...    by side, and the height of the page.
    ${layout}=    Evaluate JavaScript    ${None}
    ...    () => {
    ...        const left = document.querySelector('.app-left').getBoundingClientRect();
    ...        const right = document.querySelector('.app-right').getBoundingClientRect();
    ...        return {
    ...            side_by_side: left.right <= right.left + 1 && Math.abs(left.top - right.top) < 40,
    ...            page_height: document.documentElement.scrollHeight,
    ...        };
    ...    }
    RETURN    ${layout}

Window Should Fit
    [Documentation]    Checks that Clerk's open window (its card) is inside the screen.
    [Arguments]    ${what}    ${width}    ${height}
    ${box}=    Evaluate JavaScript    ${None}
    ...    () => {
    ...        const cards = [...document.querySelectorAll('.cl-cardBox, .cl-card')].filter((c) => c.offsetParent !== null);
    ...        if (!cards.length) return null;
    ...        const r = cards[0].getBoundingClientRect();
    ...        return { top: r.top, bottom: r.bottom, left: r.left, right: r.right };
    ...    }
    Should Not Be Equal    ${box}    ${None}    msg=The ${what} was not found
    Should Be True    ${box}[top] >= -1 and ${box}[left] >= -1 and ${box}[bottom] <= ${height} + 1 and ${box}[right] <= ${width} + 1
    ...    msg=The ${what} reaches outside the ${width}×${height} screen: ${box}