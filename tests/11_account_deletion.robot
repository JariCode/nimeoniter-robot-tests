*** Settings ***
Documentation    Suite 11: Account deletion and data protection.
...    Tests that a player can delete their account in the app, that Clerk's
...    user.deleted webhook then removes the player's game state from the test
...    database, that the webhook refuses requests without a valid signature,
...    and that signing up again with the same email starts a fresh game.
...    Clerk sends its webhooks to the backend on Render (RENDER_BACKEND_URL),
...    which uses the same test database. The free Render service sleeps when
...    idle, so it is woken up at the start of the suite and the deletion is
...    waited for up to two minutes. Check in the Clerk dashboard that the
...    webhook endpoint is enabled before running this suite.
...    The tests run in order and share one temporary account: TC11-001 creates
...    and deletes it, TC11-002 checks its game state and TC11-004 signs up
...    again with its email address.
...    Covers test cases TC11-001 - TC11-004. TC11-005 (a Clerk test event of
...    another type) and TC11-006 (checking MongoDB Atlas) are manual tests.
Resource    ../resources/common.robot
Suite Setup    Prepare Account Deletion Tests
Suite Teardown    Clean Up Suite


*** Variables ***
${WEBHOOK_PATH}    /api/webhooks/clerk


*** Test Cases ***
Deleting the account removes the Clerk user and signs the player out
    [Documentation]    TC11-001. Expected result: a new player who has started playing
    ...    deletes their account from Manage account. The player is signed out to
    ...    the landing page, and the account no longer exists: signing in with its
    ...    email address says "Couldn't find your account".
    [Tags]    browser
    Open New Session
    Sign Up    ${TEMP_EMAIL}
    ${user_id}=    Get Current User Id
    Set Suite Variable    ${TEMP_USER_ID}    ${user_id}
    ${today}=    Today Key
    ${body}=    Create Dictionary    key=walk    date=${today}
    ${response}=    Signed In Request    POST    /api/state/tasks    ${body}
    Should Be Equal As Integers    ${response.status_code}    200
    ${saved}=    Get Player State From Database    ${TEMP_USER_ID}
    Should Not Be Equal    ${saved}    ${None}    msg=The new player has no game state to delete
    Delete Account In App
    Get Element Count    ${GAME_LOADED}    ==    0
    Account Should Not Exist    ${TEMP_EMAIL}
    [Teardown]    Close Session

Webhook removes the deleted player's game state
    [Documentation]    TC11-002. Expected result: after the account has been deleted,
    ...    Clerk's user.deleted webhook reaches the backend and the player's game
    ...    state disappears from the test database (waited for up to two
    ...    minutes, because the Render service may need to wake up). It does not
    ...    come back.
    [Tags]    api
    Should Not Be Empty    ${TEMP_USER_ID}    msg=TC11-001 did not create the temporary account
    Wait Until Keyword Succeeds    2 min    5 s    Player State Should Not Exist    ${TEMP_USER_ID}
    Sleep    5s
    Player State Should Not Exist    ${TEMP_USER_ID}

Webhook refuses requests without a valid signature
    [Documentation]    TC11-003. Expected result: a forged user.deleted event for the
    ...    standard test account is refused with 400 by the backend, both locally
    ...    and on Render, when it has no signature headers and when it has made-up
    ...    signature headers. The test account's game state is not deleted.
    [Tags]    api    security
    Reset Player State    ${USER_ID}
    ${event}=    Evaluate    json.dumps({'type': 'user.deleted', 'object': 'event', 'data': {'id': $USER_ID, 'deleted': True}})    modules=json
    ${now}=    Evaluate    str(int(time.time()))    modules=time
    ${no_signature}=    Create Dictionary    Content-Type=application/json
    ${fake_signature}=    Create Dictionary    Content-Type=application/json
    ...    svix-id=msg_fake123    svix-timestamp=${now}    svix-signature=v1,ZmFrZXNpZ25hdHVyZQ==
    FOR    ${backend}    IN    ${BACKEND_URL}    ${RENDER_BACKEND_URL}
        FOR    ${headers}    IN    ${no_signature}    ${fake_signature}
            ${response}=    POST    ${backend}${WEBHOOK_PATH}    data=${event}    headers=${headers}
            ...    expected_status=any
            Run Keyword And Continue On Failure    Should Be Equal As Integers    ${response.status_code}    400
            ...    msg=${backend} accepted a forged webhook (${response.status_code})
        END
    END
    ${count}=    Count Player States    ${USER_ID}
    Should Be Equal As Integers    ${count}    1    msg=A forged webhook deleted the test account's game state

Signing up again with the same email starts a fresh game
    [Documentation]    TC11-004. Expected result: signing up again with the deleted
    ...    account's email address creates a new account with a new user id, and
    ...    the game starts from the beginning: level 1, no XP, no resources, no
    ...    tasks and only the camp built. Nothing is carried over from the deleted
    ...    account.
    [Tags]    browser
    Should Not Be Empty    ${TEMP_USER_ID}    msg=TC11-001 did not create the temporary account
    Open New Session
    Sign Up    ${TEMP_EMAIL}
    ${new_id}=    Get Current User Id
    Should Not Be Equal    ${new_id}    ${TEMP_USER_ID}    msg=The new account reused the deleted account's id
    Get Text    .header-level-number    ==    1
    Get Text    .base-world-stage    ==    CAMP
    Get Element Count    .mission    ==    0
    ${values}=    Get Elements    .resource-value
    FOR    ${value}    IN    @{values}
        Get Text    ${value}    ==    0
    END
    ${state}=    Get Game State
    Should Be Equal As Integers    ${state}[totalXp]    0
    Should Be Equal As Integers    ${state}[baseStageIndex]    -1
    Should Be Empty    ${state}[missions]
    Should Be Empty    ${state}[unlockedAchievements]
    [Teardown]    Delete Test Account And Close Session


*** Keywords ***
Prepare Account Deletion Tests
    [Documentation]    Starts the browser, wakes up the Render backend (which may be
    ...    asleep) so it can receive Clerk's webhook, picks the temporary
    ...    account's email address and signs the standard test account in for
    ...    the signature test.
    Open Test Browser
    Wait Until Keyword Succeeds    3 min    10 s    GET    ${RENDER_BACKEND_URL}/    timeout=30
    ${email}=    Generate Test Email
    Set Suite Variable    ${TEMP_EMAIL}    ${email}
    Set Suite Variable    ${TEMP_USER_ID}    ${EMPTY}
    Open New Session
    Sign In
    ${user_id}=    Get Current User Id
    Set Suite Variable    ${USER_ID}    ${user_id}

Clean Up Suite
    [Documentation]    Removes the temporary account's game state if it was left
    ...    behind, resets the test account and closes the browser.
    IF    $TEMP_USER_ID    Run Keyword And Ignore Error    Delete Player State    ${TEMP_USER_ID}
    Run Keyword And Ignore Error    Reset Player State    ${USER_ID}
    Close Browser