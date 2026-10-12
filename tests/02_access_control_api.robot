*** Settings ***
Documentation    Suite 2: Access control and user isolation.
...    Tests the backend API directly with RequestsLibrary. Every protected route
...    must require a valid Clerk session token, and a player must only ever reach
...    their own game state, tasks and companion conversation. Two players are
...    signed in at the same time in their own browser sessions: player A is the
...    standard test account and player B is a new account created for this suite.
...    Another player's task must look the same as a task that does not exist (404).
...    The browser is only used to get real session tokens from Clerk.
...    Covers test cases TC02-001 - TC02-010 and TC02-012.
...    Preconditions: the .env test account (player A) exists in the app, and the
...    Render backend is running (TC02-010 deletes player B through the Clerk webhook).
Resource    ../resources/common.robot
Suite Setup    Prepare Two Players
Suite Teardown    Clean Up Players


*** Variables ***
# A task id that does not exist. The routes check authentication before they
# look for the task, so the answer must be 401, not 404.
${UNKNOWN_TASK_ID}    1
${FORGED_TOKEN}       eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyX2ZvcmdlZCJ9.forged-signature
${MALFORMED_TOKEN}    not-a-token
# Distinctive markers that only player A's data contains
${A_TASK_ID}          ${777000111}
${A_CHAT_MARKER}      Player A private message 7f3k


*** Test Cases ***
Protected routes require authentication
    [Documentation]    TC02-001. Expected result: every protected backend route answers
    ...    401 without a session token. The list covers every route except the
    ...    public health route, GET /api/config and the Clerk webhook. All routes are
    ...    checked even if one fails, and the failures are reported together.
    [Tags]    api    security
    [Template]    Route Returns 401 Without Token
    GET       /api/state
    POST      /api/state/tasks
    POST      /api/state/tasks/${UNKNOWN_TASK_ID}/complete
    POST      /api/state/tasks/${UNKNOWN_TASK_ID}/uncomplete
    DELETE    /api/state/tasks/${UNKNOWN_TASK_ID}
    POST      /api/state/build
    GET       /api/assistant/history
    POST      /api/assistant

Forged, malformed and expired tokens are rejected
    [Documentation]    TC02-002. Expected result: a forged token, a real token whose
    ...    content was changed to impersonate another player, a malformed token
    ...    and a real token that has expired all get 401. The expired token is a
    ...    real one that the test waits to expire (about one minute).
    [Tags]    api    security
    Switch To Player    A
    ${real}=    Get Session Token
    ${tampered}=    Tamper Token Subject    ${real}    ${B_USER_ID}
    Token Is Rejected On Every Route    ${FORGED_TOKEN}
    Token Is Rejected On Every Route    ${tampered}
    Token Is Rejected On Every Route    ${MALFORMED_TOKEN}
    ${expires}=    Token Expiry Time    ${real}
    Wait Until Token Has Expired    ${expires}
    Token Is Rejected On Every Route    ${real}

Valid token gives access to the API
    [Documentation]    TC02-003. Expected result: with the signed-in player's token
    ...    the game state and the companion history answer 200.
    [Tags]    api
    Switch To Player    A
    ${response}=    Signed In Request    GET    /api/state
    Should Be Equal As Integers    ${response.status_code}    200
    ${response}=    Signed In Request    GET    /api/assistant/history
    Should Be Equal As Integers    ${response.status_code}    200

Public routes answer without authentication
    [Documentation]    TC02-004. Expected result: the health route and GET /api/config
    ...    answer 200 without a token. The config contains the public game rules:
    ...    the task catalog, the build stages and the achievements.
    [Tags]    api
    ${health}=    GET    ${BACKEND_URL}/    expected_status=any
    Should Be Equal As Integers    ${health.status_code}    200
    Should Be Equal    ${health.json()}[status]    ok
    ${config}=    GET    ${BACKEND_URL}/api/config    expected_status=any
    Should Be Equal As Integers    ${config.status_code}    200
    Should Not Be Empty    ${config.json()}[taskCatalog]
    Should Not Be Empty    ${config.json()}[buildStages]
    Should Not Be Empty    ${config.json()}[achievements]

Another player cannot touch a player's task
    [Documentation]    TC02-005. Expected result: player B cannot complete, undo or
    ...    remove player A's task by its id. Every attempt returns 404, and player
    ...    A's task and game state stay exactly as they were.
    [Tags]    api    security
    Switch To Player    A
    ${today}=    Today Key
    ${body}=    Create Dictionary    key=walk    date=${today}
    ${added}=    Signed In Request    POST    /api/state/tasks    ${body}
    Should Be Equal As Integers    ${added.status_code}    200
    ${task_id}=    Evaluate
    ...    [m['id'] for m in $added.json()['missions'] if m['key'] == 'walk' and m['date'] == $today][0]
    ${before}=    Get Game State
    Player B Gets 404    POST      /api/state/tasks/${task_id}/complete
    Player B Gets 404    POST      /api/state/tasks/${task_id}/uncomplete
    Player B Gets 404    DELETE    /api/state/tasks/${task_id}
    Switch To Player    A
    ${after}=    Get Game State
    Economy And Tasks Should Be Unchanged    ${before}    ${after}
    [Teardown]    Reset Player State    ${A_USER_ID}

Another player's state never contains the first player's data
    [Documentation]    TC02-006. Expected result: player A has XP, resources,
    ...    buildings, achievements, a streak and a task, but player B's game state
    ...    contains none of them. B only sees B's own fresh state, and the response
    ...    does not mention A's user id or A's task id.
    [Tags]    api    security
    ${today}=    Today Key
    ${a_task}=    Evaluate
    ...    {'id': $A_TASK_ID, 'date': $today, 'key': 'walk', 'name': 'Go for a walk', 'icon': '🚶', 'xp': 10, 'resources': {'wood': 2}, 'done': False}
    ${resources}=    Create Dictionary    wood=${321}    stone=${222}    food=${111}
    ${missions}=    Create List    ${a_task}
    ${achievements}=    Create List    first_task
    Seed Player State    ${A_USER_ID}    totalXp=${12345}    resources=${resources}
    ...    baseStageIndex=${3}    missions=${missions}    unlockedAchievements=${achievements}
    ...    streak=${9}
    Switch To Player    B
    ${response}=    Signed In Request    GET    /api/state
    Should Be Equal As Integers    ${response.status_code}    200
    ${state}=    Set Variable    ${response.json()}
    Should Be Equal    ${state}[clerkUserId]    ${B_USER_ID}
    Should Be Equal As Integers    ${state}[totalXp]    0
    Should Be Equal As Integers    ${state}[baseStageIndex]    -1
    Should Be Equal As Integers    ${state}[streak]    0
    Should Be Equal    ${state}[resources]    ${{{'wood': 0, 'stone': 0, 'food': 0}}}
    Should Be Empty    ${state}[missions]
    Should Be Empty    ${state}[unlockedAchievements]
    Should Not Contain    ${response.text}    ${A_USER_ID}
    Should Not Contain    ${response.text}    ${{str($A_TASK_ID)}}
    [Teardown]    Reset Player State    ${A_USER_ID}

Companion conversation is per player
    [Documentation]    TC02-007. Expected result: player A's saved companion
    ...    conversation contains a private message, and A sees it. Player B's
    ...    conversation history does not contain it.
    [Tags]    api    security
    ${message}=    Create Dictionary    role=user    content=${A_CHAT_MARKER}    ts=${0}
    ${history}=    Create List    ${message}
    Seed Player State    ${A_USER_ID}    chatHistory=${history}
    Switch To Player    A
    ${own}=    Signed In Request    GET    /api/assistant/history
    Should Contain    ${own.text}    ${A_CHAT_MARKER}
    Switch To Player    B
    ${other}=    Signed In Request    GET    /api/assistant/history
    Should Be Equal As Integers    ${other.status_code}    200
    Should Not Contain    ${other.text}    ${A_CHAT_MARKER}
    [Teardown]    Reset Player State    ${A_USER_ID}

Extra fields in the request body are ignored
    [Documentation]    TC02-008. Expected result: when fields the client must never
    ...    set (totalXp, resources, baseStageIndex, clerkUserId, unlockedAchievements,
    ...    streak, xp, done) are sent with adding, completing and building, they are
    ...    ignored. The task is added as not done with the catalog reward, completing
    ...    it does not unlock the achievements that were sent, the build is rejected
    ...    for a fresh player, and player B's state is not touched even though B's
    ...    user id was sent as clerkUserId.
    [Tags]    api    security
    Reset Player State    ${A_USER_ID}
    Switch To Player    A
    ${today}=    Today Key
    ${walk}=    Catalog Task    walk
    ${extra}=    Create Dictionary    totalXp=${99999}    baseStageIndex=${20}
    ...    clerkUserId=${B_USER_ID}    streak=${99}    xp=${9999}    done=${True}
    ...    resources=${{{'wood': 999, 'stone': 999, 'food': 999}}}
    ...    unlockedAchievements=${{['tasks_500', 'level_80']}}
    ${body}=    Copy Dictionary    ${extra}
    Set To Dictionary    ${body}    key=walk    date=${today}
    ${added}=    Signed In Request    POST    /api/state/tasks    ${body}
    Should Be Equal As Integers    ${added.status_code}    200
    ${task}=    Evaluate    [m for m in $added.json()['missions'] if m['key'] == 'walk'][0]
    Should Be Equal    ${task}[done]    ${False}
    Should Be Equal As Integers    ${task}[xp]    ${walk}[xp]
    Should Be Equal As Integers    ${added.json()}[totalXp]    0
    Should Be Equal As Integers    ${added.json()}[baseStageIndex]    -1
    Should Be Equal As Integers    ${added.json()}[streak]    0
    Should Be Empty    ${added.json()}[unlockedAchievements]
    ${body}=    Copy Dictionary    ${extra}
    Set To Dictionary    ${body}    date=${today}
    ${completed}=    Signed In Request    POST    /api/state/tasks/${task}[id]/complete    ${body}
    Should Be Equal As Integers    ${completed.status_code}    200
    Should Not Contain    ${completed.json()}[unlockedAchievements]    tasks_500
    Should Not Contain    ${completed.json()}[unlockedAchievements]    level_80
    Should Be Equal As Integers    ${completed.json()}[baseStageIndex]    -1
    ${built}=    Signed In Request    POST    /api/state/build    ${extra}
    Should Be Equal As Integers    ${built.status_code}    400
    ${b_state}=    Get Player State From Database    ${B_USER_ID}
    Should Be Empty    ${b_state}[missions]
    Should Be Equal As Integers    ${b_state}[totalXp]    0
    [Teardown]    Reset Player State    ${A_USER_ID}

Rewards sent by the client are ignored
    [Documentation]    TC02-009. Expected result: a task added with a made-up name,
    ...    icon, XP and resources gets the catalog's name, icon, XP and resources,
    ...    and completing it grants exactly the catalog reward (plus any achievement
    ...    rewards the backend itself grants, which are added to the expected value).
    [Tags]    api    security
    Reset Player State    ${A_USER_ID}
    Switch To Player    A
    ${today}=    Today Key
    ${walk}=    Catalog Task    walk
    ${body}=    Create Dictionary    key=walk    date=${today}    name=Hacked task
    ...    icon=💰    xp=${9999}    resources=${{{'wood': 9999, 'stone': 9999, 'food': 9999}}}
    ${added}=    Signed In Request    POST    /api/state/tasks    ${body}
    Should Be Equal As Integers    ${added.status_code}    200
    ${task}=    Evaluate    [m for m in $added.json()['missions'] if m['key'] == 'walk'][0]
    Should Be Equal    ${task}[name]    ${walk}[name]
    Should Be Equal    ${task}[icon]    ${walk}[icon]
    Should Be Equal As Integers    ${task}[xp]    ${walk}[xp]
    Should Be Equal    ${task}[resources]    ${walk}[resources]
    ${body}=    Create Dictionary    date=${today}    xp=${9999}
    ${completed}=    Signed In Request    POST    /api/state/tasks/${task}[id]/complete    ${body}
    Should Be Equal As Integers    ${completed.status_code}    200
    ${bonus}=    Achievement Rewards    ${completed.json()}[unlockedNow]
    ${expected_xp}=    Evaluate    $walk['xp'] + $bonus['xp']
    Should Be Equal As Integers    ${completed.json()}[totalXp]    ${expected_xp}
    FOR    ${resource}    IN    wood    stone    food
        ${expected}=    Evaluate    $walk['resources'].get($resource, 0) + $bonus[$resource]
        Should Be Equal As Integers    ${completed.json()}[resources][${resource}]    ${expected}
    END
    [Teardown]    Reset Player State    ${A_USER_ID}

Two simultaneous first loads create only one game state
    [Documentation]    TC02-012. Expected result: when a player with no game state
    ...    yet sends two requests for their state at exactly the same time, both
    ...    succeed and only one game state is created.
    [Tags]    api
    Delete Player State    ${B_USER_ID}
    Switch To Player    B
    ${token}=    Get Session Token
    ${codes}=    Send Parallel Requests    GET    ${BACKEND_URL}/api/state    ${token}    count=2
    Should Be Equal    ${codes}    ${{[200, 200]}}
    ${count}=    Count Player States    ${B_USER_ID}
    Should Be Equal As Integers    ${count}    1

Token of a deleted player is rejected
    [Documentation]    TC02-010. Expected result: when player B deletes their account,
    ...    B's still-unexpired session token is rejected (401) before it would have
    ...    expired on its own, and the Clerk webhook removes B's game state. The test
    ...    checks that the rejection happens inside the token's lifetime, so expiry
    ...    does not hide the result. This test deletes player B, so it runs last.
    [Tags]    api    security
    Switch To Player    B
    ${token}=    Get Session Token
    ${expires}=    Token Expiry Time    ${token}
    Delete Account In App
    Set Suite Variable    ${B_DELETED}    ${True}
    ${headers}=    Create Dictionary    Authorization=Bearer ${token}
    ${response}=    GET    ${BACKEND_URL}/api/state    headers=${headers}    expected_status=any
    ${now}=    Evaluate    time.time()    modules=time
    Should Be True    ${now} < ${expires}
    ...    msg=The token expired before the check, so the result proves nothing. Run the test again.
    Should Be Equal As Integers    ${response.status_code}    401
    ...    msg=The deleted player's unexpired token was accepted (${response.status_code})
    Wait Until Keyword Succeeds    30s    2s    Player State Should Not Exist    ${B_USER_ID}


*** Keywords ***
Prepare Two Players
    [Documentation]    Signs player A (the standard test account) in and resets A's
    ...    game state. Registers player B in a second browser session. The session
    ...    ids are stored so the tests can switch between the players, and both
    ...    players' Clerk user ids are stored for the database checks.
    Set Suite Variable    ${B_DELETED}    ${False}
    Open Test Browser
    ${context_a}=    New Context    viewport={'width': 1280, 'height': 900}
    New Page    ${APP_URL}
    Sign In
    Set Suite Variable    ${CONTEXT_A}    ${context_a}
    ${a_id}=    Get Current User Id
    Set Suite Variable    ${A_USER_ID}    ${a_id}
    Reset Player State    ${A_USER_ID}
    ${context_b}=    New Context    viewport={'width': 1280, 'height': 900}
    New Page    ${APP_URL}
    ${email}=    Generate Test Email
    Sign Up    ${email}
    Set Suite Variable    ${CONTEXT_B}    ${context_b}
    ${b_id}=    Get Current User Id
    Set Suite Variable    ${B_USER_ID}    ${b_id}

Clean Up Players
    [Documentation]    Resets player A's game state and deletes player B's account
    ...    through the app if TC02-010 did not already do it. B's game state is
    ...    removed from the test database in any case. If deleting B fails, a
    ...    warning is written to the report.
    Run Keyword And Ignore Error    Reset Player State    ${A_USER_ID}
    IF    not ${B_DELETED}
        Run Keyword And Ignore Error    Switch To Player    B
        ${status}    ${message}=    Run Keyword And Ignore Error    Delete Account In App
        IF    '${status}' == 'FAIL'
            Log    Deleting player B failed, remove it in the Clerk dashboard: ${message}    WARN
        END
    END
    Run Keyword And Ignore Error    Delete Player State    ${B_USER_ID}
    Close Browser

Switch To Player
    [Documentation]    Switches the active browser session to player A or B. The
    ...    session token is always taken from the active session.
    [Arguments]    ${player}
    IF    '${player}' == 'A'
        Switch Context    ${CONTEXT_A}
    ELSE
        Switch Context    ${CONTEXT_B}
    END

Route Returns 401 Without Token
    [Documentation]    Sends a request without a session token and checks that the
    ...    answer is 401.
    [Arguments]    ${method}    ${path}
    ${response}=    Run Keyword    ${method}    ${BACKEND_URL}${path}    expected_status=any
    Should Be Equal As Integers    ${response.status_code}    401
    ...    msg=${method} ${path} returned ${response.status_code}, expected 401

Route Returns 401 With Token
    [Documentation]    Sends a request with the given token and checks that the
    ...    answer is 401.
    [Arguments]    ${method}    ${path}    ${token}
    ${headers}=    Create Dictionary    Authorization=Bearer ${token}
    ${response}=    Run Keyword    ${method}    ${BACKEND_URL}${path}
    ...    headers=${headers}    expected_status=any
    Should Be Equal As Integers    ${response.status_code}    401
    ...    msg=${method} ${path} returned ${response.status_code} with an invalid token, expected 401

Token Is Rejected On Every Route
    [Documentation]    Checks that the token is rejected on a read route, a write
    ...    route and the companion route.
    [Arguments]    ${token}
    Route Returns 401 With Token    GET     /api/state                ${token}
    Route Returns 401 With Token    POST    /api/state/build          ${token}
    Route Returns 401 With Token    GET     /api/assistant/history    ${token}

Tamper Token Subject
    [Documentation]    Returns a copy of a real token whose payload says it belongs
    ...    to another user. The signature no longer matches the content.
    [Arguments]    ${token}    ${other_user_id}
    ${parts}=    Evaluate    $token.split('.')
    ${payload}=    Evaluate
    ...    json.loads(base64.urlsafe_b64decode($parts[1] + '=' * (-len($parts[1]) % 4)))
    ...    modules=json,base64
    Set To Dictionary    ${payload}    sub=${other_user_id}
    ${encoded}=    Evaluate
    ...    base64.urlsafe_b64encode(json.dumps($payload).encode()).decode().rstrip('=')
    ...    modules=json,base64
    RETURN    ${parts}[0].${encoded}.${parts}[2]

Token Expiry Time
    [Documentation]    Returns the token's expiry time (the exp field) as Unix seconds.
    [Arguments]    ${token}
    ${expires}=    Evaluate
    ...    json.loads(base64.urlsafe_b64decode($token.split('.')[1] + '=' * (-len($token.split('.')[1]) % 4)))['exp']
    ...    modules=json,base64
    RETURN    ${expires}

Wait Until Token Has Expired
    [Documentation]    Waits until the token's expiry time has passed, plus a margin
    ...    for the clock tolerance the backend allows.
    [Arguments]    ${expires}
    ${wait}=    Evaluate    max(0, ${expires} - time.time() + 10)    modules=time
    Sleep    ${wait}s

Player B Gets 404
    [Documentation]    Sends a request as player B and checks that the answer is 404.
    [Arguments]    ${method}    ${path}
    Switch To Player    B
    ${today}=    Today Key
    ${body}=    Create Dictionary    date=${today}
    ${response}=    Signed In Request    ${method}    ${path}    ${body}
    Should Be Equal As Integers    ${response.status_code}    404
    ...    msg=${method} ${path} returned ${response.status_code}, expected 404

Economy And Tasks Should Be Unchanged
    [Documentation]    Compares two game states and fails if XP, resources, the
    ...    built stage, the streak or the tasks differ.
    [Arguments]    ${before}    ${after}
    FOR    ${field}    IN    totalXp    resources    baseStageIndex    streak    missions
        Should Be Equal    ${after}[${field}]    ${before}[${field}]
        ...    msg=${field} changed: ${before}[${field}] -> ${after}[${field}]
    END

Catalog Task
    [Documentation]    Returns a task from the backend's public task catalog by key.
    [Arguments]    ${key}
    ${config}=    GET    ${BACKEND_URL}/api/config
    ${task}=    Evaluate    [t for t in $config.json()['taskCatalog'] if t['key'] == $key][0]
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