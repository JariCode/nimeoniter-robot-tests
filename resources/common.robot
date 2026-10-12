*** Settings ***
Documentation    Shared variables and keywords for the Nimeoniter tests.
...    The tests need the frontend production build (vite preview) and the
...    backend running. Settings and credentials are read from the .env file
...    (resources/settings.py). Game states are seeded straight into the test
...    database with resources/PlayerStateSeed.py.
# BrowserExtensions.js adds keywords that intercept the page's network requests
Library    Browser    jsextension=${CURDIR}/BrowserExtensions.js
Library    RequestsLibrary
Library    String
Library    Collections
Library    PlayerStateSeed.py
Library    ParallelRequests.py
Library    FrontendBuild.py
Variables    settings.py


*** Variables ***
# The landing page start button and an element that only exists once the
# signed-in player's game state has loaded
${LANDING_BUTTON}    .landing-start
${GAME_LOADED}       .base-status


*** Keywords ***
Open Test Browser
    [Documentation]    Starts the browser. Run once at the start of a suite.
    ...    Engine (BROWSER), visibility (HEADLESS) and slow-down (SLOWMO) come
    ...    from the .env file.
    New Browser    ${BROWSER}    headless=${HEADLESS}    slowMo=${SLOWMO}

Open New Session
    [Documentation]    Opens a clean browser session with no earlier sign-ins and
    ...    loads the landing page. Run at the start of every test so tests do
    ...    not affect each other. The viewport is a desktop size; responsive
    ...    tests open their own sessions.
    [Arguments]    ${width}=1280    ${height}=900
    New Context    viewport={'width': ${width}, 'height': ${height}}
    New Page    ${APP_URL}

Close Session
    [Documentation]    Closes the test's browser session. Run at the end of every test.
    Close Context

Enter Verification Code If Asked
    [Documentation]    Clerk asks for an email code when signing up ("Verify your
    ...    email") or when signing in from a new device ("Check your email").
    ...    Every Robot session looks like a new device. The code is typed once
    ...    Clerk shows the "Resend (30)" countdown, which means the code has been
    ...    sent. Sometimes Clerk has not really sent it (it answers "You need to
    ...    send a verification code before attempting to verify"); then the test
    ...    waits until the Resend button can be used, asks for a new code with it
    ...    and types the code again, up to three times. The test code comes from
    ...    the .env file and only works for +clerk_test addresses in Clerk's
    ...    development instance.
    [Arguments]    ${code}=${CLERK_TEST_CODE}
    ${asked}=    Run Keyword And Return Status
    ...    Wait For Elements State    text=/Check your email|Verify your email/    visible    timeout=5s
    IF    not ${asked}    RETURN
    ${resend}=    Set Variable    css=button:has-text("Resend")
    FOR    ${attempt}    IN RANGE    3
        ${sent}=    Run Keyword And Return Status
        ...    Wait For Elements State    text=/Resend \\(\\d+\\)/    visible    timeout=10s
        IF    not ${sent}
            Wait For Elements State    ${resend}    enabled    timeout=40s
            Click    ${resend}
            Wait For Elements State    text=/Resend \\(\\d+\\)/    visible    timeout=15s
        END
        Wait For Load State    networkidle    timeout=10s
        IF    ${attempt} > 0    Run Keyword And Ignore Error    Clear Verification Code
        Keyboard Input    type    ${code}
        ${refused}=    Run Keyword And Return Status
        ...    Wait For Elements State    text=/send a verification code before/    visible    timeout=3s
        IF    not ${refused}    RETURN
        Log    Clerk had not sent the code yet (attempt ${attempt}), asking for a new one    WARN
        Wait For Elements State    ${resend}    enabled    timeout=40s
        Click    ${resend}
    END
    Fail    Clerk did not accept the verification code after three attempts

Clear Verification Code
    [Documentation]    Empties Clerk's six code boxes and puts the cursor in the
    ...    first one, so the code can be typed from the start.
    Click    .cl-otpCodeFieldInput >> nth=5
    FOR    ${i}    IN RANGE    6
        Keyboard Key    press    Backspace
    END
    Click    .cl-otpCodeFieldInput >> nth=0

Wait For Game To Load
    [Documentation]    Waits until the signed-in player's game state has loaded and
    ...    the world is shown.
    Wait For Elements State    ${GAME_LOADED}    visible    timeout=30s

Open Sign In
    [Documentation]    Opens Clerk's sign-in window from the landing page button.
    Click    ${LANDING_BUTTON}
    Wait For Elements State    input[name="identifier"]    visible    timeout=15s

Sign In
    [Documentation]    Signs in from the landing page. If Clerk asks to verify a new
    ...    device, the test code is entered. Success is confirmed by the game
    ...    view, which is only shown to a signed-in player.
    [Arguments]    ${email}=${TEST_EMAIL}    ${password}=${TEST_PASSWORD}
    Open Sign In
    Fill Text    input[name="identifier"]    ${email}
    Click    .cl-formButtonPrimary
    Fill Text    input[name="password"]    ${password}
    Click    .cl-formButtonPrimary
    Enter Verification Code If Asked
    Wait For Game To Load

Generate Test Email
    [Documentation]    Returns a random Clerk test email address. The +clerk_test
    ...    suffix means no email is sent and the verification code is Clerk's
    ...    test code. The prefix and domain come from the .env file.
    ${suffix}=    Generate Random String    8    [LOWER][NUMBERS]
    RETURN    ${TEST_EMAIL_PREFIX}+clerk_test_${suffix}@${TEST_EMAIL_DOMAIN}

Sign Up
    [Documentation]    Opens the sign-in window, switches to sign-up and creates an
    ...    account. Clerk's email verification is passed with the test code.
    [Arguments]    ${email}    ${password}=${TEST_PASSWORD}
    Open Sign In
    Click    .cl-footerActionLink
    Fill Text    input[name="emailAddress"]    ${email}
    Fill Text    input[name="password"]    ${password}
    Click    .cl-formButtonPrimary
    Enter Verification Code If Asked
    Wait For Game To Load

Open User Menu
    [Documentation]    Opens Clerk's user menu from the avatar in the top-right corner.
    Click    .cl-userButtonTrigger
    Wait For Elements State    .cl-userButtonPopoverCard    visible    timeout=10s

Sign Out
    [Documentation]    Signs out from the user menu and waits for the landing page.
    Open User Menu
    Click    text=Sign out
    Wait For Elements State    ${LANDING_BUTTON}    visible    timeout=15s

Open Profile Window
    [Documentation]    Opens Clerk's Manage account window from the user menu.
    Open User Menu
    Click    text=Manage account
    Wait For Elements State    .cl-userProfile-root    visible    timeout=10s

Close Profile Window
    [Documentation]    Closes Clerk's Manage account window.
    Click    .cl-modalCloseButton
    Wait For Elements State    .cl-userProfile-root    detached    timeout=10s

Close Open Windows
    [Documentation]    Closes any Clerk windows left open with Escape so they don't
    ...    cover the page. Windows can be stacked, for example the password
    ...    confirmation on top of the profile window.
    FOR    ${i}    IN RANGE    3
        ${open}=    Get Element Count    .cl-modalBackdrop
        IF    ${open} == 0    BREAK
        Keyboard Key    press    Escape
        Sleep    0.5s
    END

Confirm With Password If Asked
    [Documentation]    Clerk asks for the current password before sensitive actions
    ...    such as deleting the account ("Verification required"). If the
    ...    password field appears, the password is entered and Continue is
    ...    pressed. Otherwise nothing is done. Continue is chosen by its text,
    ...    because another button with the same class is behind it.
    [Arguments]    ${password}=${TEST_PASSWORD}
    ${asked}=    Run Keyword And Return Status
    ...    Wait For Elements State    input[name="password"]    visible    timeout=5s
    IF    ${asked}
        Fill Text    input[name="password"]    ${password}
        Click    .cl-formButtonPrimary >> text=Continue
    END

Delete Account In App
    [Documentation]    Deletes the signed-in player's account from Clerk's profile
    ...    window like a real player. Clerk asks for the current password after
    ...    the confirmation. Clerk then sends a webhook to the backend, which
    ...    removes the player's game state.
    [Arguments]    ${password}=${TEST_PASSWORD}
    Open Profile Window
    Click    text=Security
    Click    button >> text=Delete account
    Fill Text    input[name="deleteConfirmation"]    Delete account
    Click    button[data-localization-key="userProfile.deletePage.confirm"]
    Confirm With Password If Asked    ${password}
    Wait For Elements State    ${LANDING_BUTTON}    visible    timeout=20s

Account Should Not Exist
    [Documentation]    Tries to sign in with the email address. Clerk cannot find
    ...    the account and shows "Couldn't find your account".
    [Arguments]    ${email}
    Open Sign In
    Fill Text    input[name="identifier"]    ${email}
    Click    .cl-formButtonPrimary
    Wait For Elements State    .cl-formFieldErrorText    visible    timeout=10s
    Get Text    .cl-formFieldErrorText    contains    Couldn't find your account

Delete Test Account And Close Session
    [Documentation]    Teardown for tests that create their own account: closes any
    ...    open windows, deletes the account through the app, removes its game
    ...    state from the test database and closes the session. If the deletion
    ...    fails, a warning is written to the report and the account is removed
    ...    by hand from the Clerk dashboard.
    [Arguments]    ${password}=${TEST_PASSWORD}
    Run Keyword And Ignore Error    Close Open Windows
    ${user_id}=    Run Keyword And Ignore Error    Get Current User Id
    ${status}    ${message}=    Run Keyword And Ignore Error    Delete Account In App    ${password}
    IF    '${status}' == 'FAIL'
        Log    Deleting the test account failed, remove it in the Clerk dashboard: ${message}    WARN
    END
    IF    '${user_id}[0]' == 'PASS' and $user_id[1]
        Delete Player State    ${user_id}[1]
    END
    Close Session

Get Current User Id
    [Documentation]    Returns the signed-in player's Clerk user id from the browser.
    ${user_id}=    Evaluate JavaScript    ${None}    () => window.Clerk.user.id
    RETURN    ${user_id}

Get Session Token
    [Documentation]    Gets the signed-in player's session token (JWT) straight from
    ...    Clerk inside the browser. The token is short-lived, so it is always
    ...    fetched right before an API call. Needs a signed-in player in the
    ...    browser.
    ${token}=    Evaluate JavaScript    ${None}    async () => await window.Clerk.session.getToken()
    RETURN    ${token}

Signed In Request
    [Documentation]    Sends a request to the backend with the signed-in player's
    ...    token and returns the response. The status code is not checked here
    ...    but in the test. The path starts with /api.
    [Arguments]    ${method}    ${path}    ${body}=${None}
    ${token}=    Get Session Token
    ${headers}=    Create Dictionary    Authorization=Bearer ${token}
    ${response}=    Run Keyword    ${method}    ${BACKEND_URL}${path}
    ...    headers=${headers}    json=${body}    expected_status=any
    RETURN    ${response}

Get Game State
    [Documentation]    Returns the signed-in player's game state from the backend.
    ${response}=    Signed In Request    GET    /api/state
    Should Be Equal As Integers    ${response.status_code}    200
    RETURN    ${response.json()}

Today Key
    [Documentation]    Returns today's date as YYYY-MM-DD in the browser's local
    ...    time, the same way the app's todayKey() does.
    ${today}=    Evaluate JavaScript    ${None}
    ...    () => { const d = new Date(); const p = (n) => String(n).padStart(2, '0'); return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()); }
    RETURN    ${today}

Reload Game
    [Documentation]    Reloads the page and waits for the game to load again, so the
    ...    user interface shows the game state just seeded in the database.
    Reload
    Wait For Game To Load

Get Task Catalog
    [Documentation]    Returns the task catalog from the backend's public game rules.
    ${config}=    GET    ${BACKEND_URL}/api/config
    RETURN    ${config.json()}[taskCatalog]

Catalog Task
    [Documentation]    Returns a task from the backend's public task catalog by key.
    [Arguments]    ${key}
    ${catalog}=    Get Task Catalog
    ${task}=    Evaluate    [t for t in $catalog if t['key'] == $key][0]
    RETURN    ${task}

Achievement Rewards
    [Documentation]    Returns the summed XP and resource rewards of the given
    ...    achievement ids, taken from the backend's public achievement list.
    [Arguments]    ${ids}
    ${config}=    GET    ${BACKEND_URL}/api/config
    ${earned}=    Evaluate    [a for a in $config.json()['achievements'] if a['id'] in $ids]
    ${total}=    Create Dictionary
    FOR    ${key}    IN    xp    wood    stone    food
        ${sum}=    Evaluate    sum(a['reward'].get('${key}', 0) for a in $earned)
        Set To Dictionary    ${total}    ${key}=${sum}
    END
    RETURN    ${total}