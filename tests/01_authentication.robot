*** Settings ***
Documentation    Suite 1: Authentication, session and profile.
...    Tests sign-up, sign-in, the session, signing out, Clerk's Manage account
...    window and that Clerk telemetry is off. Tests that change a profile register
...    their own test user and delete it at the end, so the standard test account
...    stays unchanged. The new password for the password-change test comes from
...    the .env file (NEW_PASSWORD).
...    Covers test cases TC01-001 - TC01-012 and TC01-019.
...    Preconditions: the .env test account exists in the app, and the Render
...    backend is running (account deletion goes through the Clerk webhook).
Resource    ../resources/common.robot
Suite Setup    Open Test Browser
Suite Teardown    Close Browser
Test Setup    Open New Session
Test Teardown    Close Session


*** Variables ***
${WRONG_PASSWORD}    WrongPassword123!
${WRONG_CODE}        000000


*** Test Cases ***
Landing page opens the sign-in
    [Documentation]    TC01-001. Expected result: the landing page shows the title and
    ...    the "Light the fire" button, and the button opens Clerk's sign-in window.
    [Tags]    browser
    Get Text    .landing-title    ==    NIMEONITER
    Get Text    ${LANDING_BUTTON}    matches    (?i)^light the fire$
    Open Sign In

Sign-up creates an account and a fresh game
    [Documentation]    TC01-002. Expected result: a new account is created with a
    ...    random test email and the game opens with a fresh game state: level 1,
    ...    0 XP, no resources, the starting camp, the well as the next building and
    ...    no tasks. The backend has exactly one game state for the new player.
    [Tags]    browser    api
    ${email}=    Generate Test Email
    Sign Up    ${email}
    Get Text    .header-level-number    ==    1
    Get Text    .base-world-stage    ==    CAMP
    Get Text    .base-build-label    ==    NEXT: WELL
    Get Text    .mission-list-empty    contains    No tasks yet
    ${values}=    Get Texts Of Resources
    Should Be Equal    ${values}    ${{['0', '0', '0']}}
    ${state}=    Get Game State
    Should Be Equal As Integers    ${state}[totalXp]    0
    Should Be Equal As Integers    ${state}[baseStageIndex]    -1
    Should Be Equal As Integers    ${state}[streak]    0
    Should Be Empty    ${state}[missions]
    Should Be Equal    ${state}[resources]    ${{{'wood': 0, 'stone': 0, 'food': 0}}}
    ${user_id}=    Get Current User Id
    ${count}=    Count Player States    ${user_id}
    Should Be Equal As Integers    ${count}    1
    [Teardown]    Delete Test Account And Close Session

Sign-in with the test account works
    [Documentation]    TC01-003. Expected result: with correct credentials the player
    ...    gets in and the game view is shown.
    [Tags]    browser
    Sign In
    Get Element States    .header-level    contains    visible

Wrong password is rejected
    [Documentation]    TC01-004. Expected result: a wrong password does not sign in,
    ...    Clerk shows an error and the game does not open.
    [Tags]    browser    security
    Open Sign In
    Fill Text    input[name="identifier"]    ${TEST_EMAIL}
    Click    .cl-formButtonPrimary
    Fill Text    input[name="password"]    ${WRONG_PASSWORD}
    Click    .cl-formButtonPrimary
    Wait For Elements State    .cl-formFieldErrorText    visible    timeout=10s
    Get Element Count    ${GAME_LOADED}    ==    0

Unknown email address is rejected
    [Documentation]    TC01-005. Expected result: an email address with no account is
    ...    rejected with "Couldn't find your account".
    [Tags]    browser    security
    ${email}=    Generate Test Email
    Account Should Not Exist    ${email}
    Get Element Count    ${GAME_LOADED}    ==    0

Session persists over a page reload
    [Documentation]    TC01-006. Expected result: after a reload the player is still
    ...    signed in and the game is shown without signing in again.
    [Tags]    browser
    Sign In
    Reload Game

Signing out returns to the landing page
    [Documentation]    TC01-007. Expected result: after signing out the landing page
    ...    is shown, and the game does not come back on reload.
    [Tags]    browser    security
    Sign In
    Sign Out
    Reload
    Wait For Elements State    ${LANDING_BUTTON}    visible    timeout=15s
    Get Element Count    ${GAME_LOADED}    ==    0

No game view without signing in
    [Documentation]    TC01-008. Expected result: a signed-out visitor only sees the
    ...    landing page. No tasks, world, resources or companion are rendered.
    [Tags]    browser    security
    Wait For Elements State    ${LANDING_BUTTON}    visible    timeout=15s
    Get Element Count    .header    ==    0
    Get Element Count    .mission-list    ==    0
    Get Element Count    .base-status    ==    0
    Get Element Count    .resource-bar    ==    0
    Get Element Count    .assistant__figure    ==    0

User menu shows the signed-in email address
    [Documentation]    TC01-009. Expected result: the user menu opens from the avatar
    ...    and shows the signed-in player's email address.
    [Tags]    browser
    Sign In
    Open User Menu
    Get Text    .cl-userButtonPopoverCard    contains    ${TEST_EMAIL}

Manage account uses the dark theme and saves a name change
    [Documentation]    TC01-010. Expected result: the Manage account window opens in
    ...    the game's dark theme (dark navigation background), and a first-name
    ...    change is saved to the Clerk user.
    [Tags]    browser
    ${email}=    Generate Test Email
    Sign Up    ${email}
    ${name}=    Generate Random String    6    [LOWER]
    ${name}=    Set Variable    Robot${name}
    Open Profile Window
    Get Style    .cl-navbar    background-color    ==    rgb(17, 17, 17)
    Click    .cl-profileSectionPrimaryButton__profile
    Fill Text    input[name="firstName"]    ${name}
    Click    .cl-formButtonPrimary
    Wait For Elements State    input[name="firstName"]    detached    timeout=10s
    Close Profile Window
    ${saved}=    Evaluate JavaScript    ${None}    () => window.Clerk.user.firstName
    Should Be Equal    ${saved}    ${name}
    [Teardown]    Delete Test Account And Close Session

Password change works
    [Documentation]    TC01-011. Expected result: when the password is changed in
    ...    Manage account, Clerk asks for the current password, and after the
    ...    change the old password no longer signs in but the new one does.
    [Tags]    browser    security
    ${email}=    Generate Test Email
    Sign Up    ${email}
    Open Profile Window
    Click    text=Security
    Click    .cl-profileSectionPrimaryButton__password
    ${current}=    Get Element Count    input[name="currentPassword"]
    IF    ${current} > 0
        Fill Text    input[name="currentPassword"]    ${TEST_PASSWORD}
    END
    Fill Text    input[name="newPassword"]    ${NEW_PASSWORD}
    Fill Text    input[name="confirmPassword"]    ${NEW_PASSWORD}
    Click    .cl-formButtonPrimary
    Confirm With Password If Asked    ${TEST_PASSWORD}
    Wait For Elements State    input[name="newPassword"]    detached    timeout=15s
    Close Profile Window
    Sign Out
    Open Sign In
    Fill Text    input[name="identifier"]    ${email}
    Click    .cl-formButtonPrimary
    Fill Text    input[name="password"]    ${TEST_PASSWORD}
    Click    .cl-formButtonPrimary
    Wait For Elements State    .cl-formFieldErrorText    visible    timeout=10s
    Get Element Count    ${GAME_LOADED}    ==    0
    Close Context
    Open New Session
    Sign In    ${email}    ${NEW_PASSWORD}
    [Teardown]    Delete Test Account And Close Session    ${NEW_PASSWORD}

Clerk telemetry is off
    [Documentation]    TC01-012. Expected result: while the player signs in, uses the
    ...    game and opens the user menu, no request is sent to Clerk's telemetry
    ...    service and no telemetry key is written to local storage.
    [Tags]    browser    security
    Sign In
    Open User Menu
    Keyboard Key    press    Escape
    Reload Game
    ${telemetry_requests}=    Evaluate JavaScript    ${None}
    ...    () => performance.getEntriesByType('resource').filter((e) => e.name.includes('clerk-telemetry')).length
    Should Be Equal As Integers    ${telemetry_requests}    0
    ${key}=    Evaluate JavaScript    ${None}
    ...    () => window.localStorage.getItem('clerk_telemetry_throttler')
    Should Be Equal    ${key}    ${None}

Wrong verification code at sign-up is rejected
    [Documentation]    TC01-019. Expected result: a wrong email verification code at
    ...    sign-up is rejected with an error, the game does not open, and no
    ...    account is created.
    [Tags]    browser    security
    ${email}=    Generate Test Email
    Open Sign In
    Click    .cl-footerActionLink
    Fill Text    input[name="emailAddress"]    ${email}
    Fill Text    input[name="password"]    ${TEST_PASSWORD}
    Click    .cl-formButtonPrimary
    Enter Verification Code If Asked    ${WRONG_CODE}
    Wait For Elements State    text=Incorrect code >> nth=0    visible    timeout=10s
    Get Element Count    ${GAME_LOADED}    ==    0
    Close Context
    Open New Session
    Account Should Not Exist    ${email}


*** Keywords ***
Get Texts Of Resources
    [Documentation]    Returns the wood, stone and food values shown in the resource bar.
    ${elements}=    Get Elements    .resource-value
    ${values}=    Create List
    FOR    ${element}    IN    @{elements}
        ${text}=    Get Text    ${element}
        Append To List    ${values}    ${text}
    END
    RETURN    ${values}