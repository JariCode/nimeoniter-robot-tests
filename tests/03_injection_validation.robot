*** Settings ***
Documentation    Suite 3: Injection, XSS and input validation.
...    Tests that every input to the backend is validated and that MongoDB operator
...    injection, prototype pollution and type confusion have no effect. In the XSS
...    tests, payloads are stored in the game (with the seed helper, so no OpenAI
...    call is made) and the test checks that they are shown as text and their code
...    never runs. Also tests error handling, unknown routes and methods, and the
...    rate limits. Test inputs are based on attack techniques described by OWASP.
...    Covers test cases TC03-001 - TC03-021.
...    TC03-010 makes real OpenAI calls (tag ai). TC03-018 and TC03-019 need the
...    backend's original rate limits and are run separately (tag rate-limit).
...    TC03-019 uses its own temporary player, so the standard test account's
...    companion is not locked by the AI rate limit.
...    Precondition: the .env test account exists in the app.
Resource    ../resources/common.robot
Suite Setup    Sign In For API Tests
Suite Teardown    Clean Up Suite


*** Variables ***
# Marker an injected script would set if it ever ran
${XSS_CHECK}           () => window.__xss === undefined
@{XSS_PAYLOADS}        <script>window.__xss = 1</script>
...                    <img src=x onerror="window.__xss = 2">
...                    <svg onload="window.__xss = 3"></svg>
...                    "><iframe src="javascript:window.__xss = 4">
@{INHERITED_NAMES}     constructor    toString    __proto__    hasOwnProperty
@{INVALID_DATES}       2026-02-30    2026-13-01    2026-1-5    today    ${EMPTY}
...                    2026-10-12T00:00:00Z    12.10.2026
# Fragments that must never appear in an error response
@{INTERNAL_DETAILS}    stack    node_modules    SyntaxError    TypeError    .js:
...                    Mongo    express    at Object


*** Test Cases ***
MongoDB operators in the request body are removed
    [Documentation]    TC03-001. Expected result: MongoDB operators ($ne, $gt, $regex,
    ...    $where) sent in place of the task key or date are removed by the
    ...    backend, so the request is rejected (400) and no task is added.
    [Tags]    api    security
    ${today}=    Today Key
    Request Is Rejected With 400    POST    /api/state/tasks    ${{{'key': {'$ne': None}, 'date': $today}}}
    Request Is Rejected With 400    POST    /api/state/tasks    ${{{'key': {'$regex': '.*'}, 'date': $today}}}
    Request Is Rejected With 400    POST    /api/state/tasks    ${{{'key': 'walk', 'date': {'$gt': ''}}}}
    Request Is Rejected With 400    POST    /api/state/tasks    ${{{'key': {'$where': 'sleep(1000)'}, 'date': $today}}}
    No Tasks Should Exist
    [Teardown]    Reset Test Player

Dotted keys in the request body are removed
    [Documentation]    TC03-002. Expected result: keys containing a dot (for example
    ...    resources.wood or missions.0.done), even nested ones, are removed and have
    ...    no effect. The task is added normally, as not done, and the player's XP
    ...    and resources do not change.
    [Tags]    api    security
    ${today}=    Today Key
    ${body}=    Evaluate
    ...    {'key': 'walk', 'date': $today, 'resources.wood': 999, 'missions.0.done': True, 'nested': {'totalXp.x': 5}}
    ${response}=    Signed In Request    POST    /api/state/tasks    ${body}
    Should Be Equal As Integers    ${response.status_code}    200
    Should Be Equal As Integers    ${response.json()}[resources][wood]    0
    Should Be Equal As Integers    ${response.json()}[totalXp]    0
    ${task}=    Evaluate    [m for m in $response.json()['missions'] if m['key'] == 'walk'][0]
    Should Be Equal    ${task}[done]    ${False}
    [Teardown]    Reset Test Player

Prototype pollution has no effect
    [Documentation]    TC03-003. Expected result: __proto__ and constructor keys in the
    ...    request body do not change the application's behaviour. The task is
    ...    added with the catalog reward, and later requests return normal data
    ...    with no injected fields.
    [Tags]    api    security
    ${today}=    Today Key
    ${body}=    Evaluate
    ...    json.loads('{"key": "walk", "date": "' + $today + '", "__proto__": {"isAdmin": true, "xp": 9999}, "constructor": {"prototype": {"polluted": "yes"}}}')
    ...    modules=json
    ${response}=    Signed In Request    POST    /api/state/tasks    ${body}
    Should Be Equal As Integers    ${response.status_code}    200
    ${task}=    Evaluate    [m for m in $response.json()['missions'] if m['key'] == 'walk'][0]
    Should Be Equal As Integers    ${task}[xp]    10
    ${state}=    Signed In Request    GET    /api/state
    Should Not Contain    ${state.text}    isAdmin
    Should Not Contain    ${state.text}    polluted
    ${config}=    GET    ${BACKEND_URL}/api/config
    Should Not Contain    ${config.text}    polluted
    [Teardown]    Reset Test Player

Inherited object property names are rejected
    [Documentation]    TC03-004. Expected result: names every JavaScript object
    ...    inherits (constructor, toString, __proto__, hasOwnProperty) are not real
    ...    tasks or companion modes. They are rejected as a task key (400) and as a
    ...    companion mode (400), and no task is added. All names are checked even
    ...    if one fails.
    [Tags]    api    security
    ${today}=    Today Key
    FOR    ${name}    IN    @{INHERITED_NAMES}
        Run Keyword And Continue On Failure    Request Is Rejected With 400
        ...    POST    /api/state/tasks    ${{{'key': $name, 'date': $today}}}
        Run Keyword And Continue On Failure    Request Is Rejected With 400
        ...    POST    /api/assistant    ${{{'mode': $name}}}
    END
    No Tasks Should Exist
    [Teardown]    Reset Test Player

Inherited object property name is ignored as a holiday
    [Documentation]    TC03-004 (holiday part). Expected result: a greeting request
    ...    with an inherited property name as the holiday is answered normally,
    ...    like a greeting with no holiday. The holiday text the backend adds to the
    ...    prompt is not visible from outside, so the test checks that the request
    ...    succeeds with a normal reply. Makes a real OpenAI call.
    [Tags]    api    security    ai
    ${body}=    Create Dictionary    mode=greeting    holiday=constructor    timeOfDay=day
    ${response}=    Signed In Request    POST    /api/assistant    ${body}
    Should Be Equal As Integers    ${response.status_code}    200
    Should Not Be Empty    ${response.json()}[message]
    Should Not Contain    ${response.json()}[message]    function
    [Teardown]    Reset Test Player

Type confusion is rejected
    [Documentation]    TC03-005. Expected result: a number, array, object or null in
    ...    place of the task key or date is rejected (400) and no task is added.
    [Tags]    api    security
    ${today}=    Today Key
    FOR    ${value}    IN    ${123}    ${{['walk']}}    ${{{'k': 'walk'}}}    ${None}    ${True}
        Run Keyword And Continue On Failure    Request Is Rejected With 400
        ...    POST    /api/state/tasks    ${{{'key': $value, 'date': $today}}}
        Run Keyword And Continue On Failure    Request Is Rejected With 400
        ...    POST    /api/state/tasks    ${{{'key': 'walk', 'date': $value}}}
    END
    No Tasks Should Exist
    [Teardown]    Reset Test Player

Task date must be a real calendar date
    [Documentation]    TC03-006. Expected result: a task date must be a real calendar
    ...    date in YYYY-MM-DD format. Impossible dates, wrong formats, words and an
    ...    empty value are rejected (400), and no task is added.
    [Tags]    api
    FOR    ${date}    IN    @{INVALID_DATES}
        Run Keyword And Continue On Failure    Request Is Rejected With 400
        ...    POST    /api/state/tasks    ${{{'key': 'walk', 'date': $date}}}
    END
    No Tasks Should Exist
    [Teardown]    Reset Test Player

Unknown task key is rejected
    [Documentation]    TC03-007. Expected result: a task key that is not in the
    ...    catalog is rejected (400) and no task is added.
    [Tags]    api
    ${today}=    Today Key
    Request Is Rejected With 400    POST    /api/state/tasks    ${{{'key': 'fly_to_the_moon', 'date': $today}}}
    Request Is Rejected With 400    POST    /api/state/tasks    ${{{'key': 'WALK', 'date': $today}}}
    No Tasks Should Exist
    [Teardown]    Reset Test Player

Same task cannot be added twice to the same day
    [Documentation]    TC03-008. Expected result: adding the same task a second time to
    ...    the same day is rejected (400), but the same task can be added to
    ...    another day. The day then has the task only once.
    [Tags]    api
    ${today}=    Today Key
    ${tomorrow}=    Evaluate
    ...    (datetime.date.fromisoformat($today) + datetime.timedelta(days=1)).isoformat()
    ...    modules=datetime
    ${body}=    Create Dictionary    key=walk    date=${today}
    ${first}=    Signed In Request    POST    /api/state/tasks    ${body}
    Should Be Equal As Integers    ${first.status_code}    200
    Request Is Rejected With 400    POST    /api/state/tasks    ${body}
    ${body}=    Create Dictionary    key=walk    date=${tomorrow}
    ${other_day}=    Signed In Request    POST    /api/state/tasks    ${body}
    Should Be Equal As Integers    ${other_day.status_code}    200
    ${state}=    Get Game State
    ${count}=    Evaluate    len([m for m in $state['missions'] if m['key'] == 'walk' and m['date'] == $today])
    Should Be Equal As Integers    ${count}    1
    [Teardown]    Reset Test Player

Non-numeric or unknown task id returns 404
    [Documentation]    TC03-009. Expected result: completing, undoing or removing a
    ...    task with a non-numeric, negative, huge or unknown id returns 404, and
    ...    the server keeps working afterwards.
    [Tags]    api    security
    ${today}=    Today Key
    ${body}=    Create Dictionary    date=${today}
    FOR    ${id}    IN    abc    -1    1e999    99999999999999999999    123456789    %00
        FOR    ${action}    IN    complete    uncomplete
            ${response}=    Signed In Request    POST    /api/state/tasks/${id}/${action}    ${body}
            Run Keyword And Continue On Failure    Should Be Equal As Integers    ${response.status_code}    404
            ...    msg=POST /api/state/tasks/${id}/${action} returned ${response.status_code}, expected 404
        END
        ${response}=    Signed In Request    DELETE    /api/state/tasks/${id}
        Run Keyword And Continue On Failure    Should Be Equal As Integers    ${response.status_code}    404
        ...    msg=DELETE /api/state/tasks/${id} returned ${response.status_code}, expected 404
    END
    ${state}=    Signed In Request    GET    /api/state
    Should Be Equal As Integers    ${state.status_code}    200

Companion question input is cleaned
    [Documentation]    TC03-010. Expected result: a question that is not a string is
    ...    ignored and a whitespace-only question counts as no question; both are
    ...    saved as "(spoke)". A question over 300 characters is cut to 300 before it
    ...    is saved. Makes real OpenAI calls.
    [Tags]    api    ai
    ${response}=    Signed In Request    POST    /api/assistant    ${{{'mode': 'question', 'question': 12345}}}
    Should Be Equal As Integers    ${response.status_code}    200
    Last Player Message Should Be    ${response}    (spoke)
    ${response}=    Signed In Request    POST    /api/assistant    ${{{'mode': 'question', 'question': ' ' * 5}}}
    Should Be Equal As Integers    ${response.status_code}    200
    Last Player Message Should Be    ${response}    (spoke)
    ${long}=    Evaluate    'Is this long question cut? ' + 'x' * 400
    ${response}=    Signed In Request    POST    /api/assistant    ${{{'mode': 'question', 'question': $long}}}
    Should Be Equal As Integers    ${response.status_code}    200
    ${saved}=    Evaluate    [m['content'] for m in $response.json()['history'] if m['role'] == 'user'][-1]
    Length Should Be    ${saved}    300
    [Teardown]    Reset Test Player

Unknown companion mode is rejected
    [Documentation]    TC03-011. Expected result: an unknown, wrongly cased, empty or
    ...    missing companion mode is rejected (400) before any OpenAI call, and
    ...    nothing is added to the conversation.
    [Tags]    api    security
    Request Is Rejected With 400    POST    /api/assistant    ${{{'mode': 'hack'}}}
    Request Is Rejected With 400    POST    /api/assistant    ${{{'mode': 'GREETING'}}}
    Request Is Rejected With 400    POST    /api/assistant    ${{{'mode': ''}}}
    Request Is Rejected With 400    POST    /api/assistant    ${{{'question': 'no mode'}}}
    ${history}=    Signed In Request    GET    /api/assistant/history
    Should Be Empty    ${history.json()}[history]

Request body over 100 kB is rejected with 413
    [Documentation]    TC03-012. Expected result: a request body larger than the
    ...    backend's 100 kB limit is rejected with 413 (Payload Too Large) and a
    ...    generic error, and no task is added.
    [Tags]    api    security
    ${today}=    Today Key
    ${data}=    Evaluate    json.dumps({'key': 'walk', 'date': $today, 'padding': 'x' * 120000})    modules=json
    ${response}=    Signed In Raw Request    POST    /api/state/tasks    ${data}
    Should Be Equal As Integers    ${response.status_code}    413
    Response Should Not Reveal Internals    ${response}
    No Tasks Should Exist
    [Teardown]    Reset Test Player

Malformed JSON body is rejected with 400
    [Documentation]    TC03-013. Expected result: a request body that is not valid
    ...    JSON is rejected with 400 (Bad Request) and a generic error.
    [Tags]    api    security
    ${response}=    Signed In Raw Request    POST    /api/state/tasks    {"key": "walk", "date":
    Should Be Equal As Integers    ${response.status_code}    400
    Response Should Not Reveal Internals    ${response}

HTML and script in a player message are shown as text
    [Documentation]    TC03-014. Expected result: player messages containing HTML and
    ...    script (<script>, <img onerror>, <svg onload> and a broken-out iframe) are
    ...    shown in the companion chat exactly as typed, as text. No code runs and
    ...    no element is created from them. The messages are written with the seed
    ...    helper and the greeting is skipped, so no OpenAI call is made.
    [Tags]    browser    security
    ${history}=    Create List
    FOR    ${payload}    IN    @{XSS_PAYLOADS}
        Append To List    ${history}    ${{{'role': 'user', 'content': $payload, 'ts': 0}}}
    END
    Seed Player State    ${USER_ID}    chatHistory=${history}
    Open Companion Without Greeting
    FOR    ${payload}    IN    @{XSS_PAYLOADS}
        Get Text    .assistant__log    contains    ${payload}
    END
    Get Element Count    .assistant__log script, .assistant__log img, .assistant__log svg, .assistant__log iframe    ==    0
    ${safe}=    Evaluate JavaScript    ${None}    ${XSS_CHECK}
    Should Be True    ${safe}    msg=An injected script ran
    [Teardown]    Close Companion And Reset

HTML in a companion reply is shown as text
    [Documentation]    TC03-015. Expected result: a companion reply containing HTML is
    ...    shown as text. The tags are visible as written, no bold element or image
    ...    is created and no code runs.
    [Tags]    browser    security
    ${reply}=    Set Variable    <b>bold</b><img src=x onerror="window.__xss = 5">
    ${message}=    Create Dictionary    role=assistant    content=${reply}    ts=${0}
    ${history}=    Create List    ${message}
    Seed Player State    ${USER_ID}    chatHistory=${history}
    Open Companion Without Greeting
    Get Text    .chat-msg--them    contains    <b>bold</b>
    Get Element Count    .assistant__log b, .assistant__log img    ==    0
    ${safe}=    Evaluate JavaScript    ${None}    ${XSS_CHECK}
    Should Be True    ${safe}    msg=An injected script ran
    [Teardown]    Close Companion And Reset

XSS payloads in the task search are not executed
    [Documentation]    TC03-016. Expected result: XSS payloads typed into the task
    ...    search field only filter the list. Nothing matches, the "No tasks match"
    ...    message shows the payload as text, and no code runs.
    [Tags]    browser    security
    Reload Game
    Click    .add-task-button
    FOR    ${payload}    IN    @{XSS_PAYLOADS}
        Fill Text    .add-task-search    ${payload}
        Get Text    .add-task-empty    contains    ${payload}
        Get Element Count    .add-task-option    ==    0
    END
    Get Element Count    .add-task-modal script, .add-task-modal img, .add-task-modal svg, .add-task-modal iframe    ==    0
    ${safe}=    Evaluate JavaScript    ${None}    ${XSS_CHECK}
    Should Be True    ${safe}    msg=An injected script ran
    Click    .add-task-done

Unknown routes return a clean 404
    [Documentation]    TC03-017. Expected result: unknown routes, with and without a
    ...    session token, return 404 with the JSON error "Route not found" and
    ...    nothing else.
    [Tags]    api
    ${response}=    GET    ${BACKEND_URL}/api/does-not-exist    expected_status=any
    Clean 404 Response    ${response}
    ${response}=    Signed In Request    GET    /api/state/does-not-exist
    Clean 404 Response    ${response}
    ${response}=    Signed In Request    GET    /api/../../etc/passwd
    Should Be Equal As Integers    ${response.status_code}    404

General rate limit returns 429
    [Documentation]    TC03-018. Expected result: when one IP address sends more than
    ...    100 requests within a minute, the next request returns 429 with the
    ...    rate-limit headers. Needs the backend's original limit (100 per minute),
    ...    so it is excluded from normal runs and run separately.
    [Tags]    api    security    rate-limit
    FOR    ${i}    IN RANGE    110
        ${response}=    GET    ${BACKEND_URL}/api/config    expected_status=any
        IF    ${response.status_code} == 429    BREAK
    END
    Should Be Equal As Integers    ${response.status_code}    429
    ...    msg=No 429 after 110 requests. Is the backend running with the original limit of 100?
    Should Be Equal    ${response.headers}[RateLimit-Limit]    100

AI rate limit returns 429 per player
    [Documentation]    TC03-019. Expected result: when a player sends more than 20
    ...    companion requests within 10 minutes, the 21st returns 429 with a friendly
    ...    message. The limit is counted per player: another player still gets
    ...    through. The requests use an unknown mode, which the limiter counts but
    ...    the backend rejects before any OpenAI call, so nothing is paid. A
    ...    temporary player is used so the standard account is not locked.
    ...    Tagged rate-limit: it needs the backend's original AI limit (20).
    [Tags]    api    security    rate-limit
    ${temp_context}=    New Context    viewport={'width': 1280, 'height': 900}
    Set Test Variable    ${TEMP_CONTEXT}    ${temp_context}
    New Page    ${APP_URL}
    ${email}=    Generate Test Email
    Sign Up    ${email}
    FOR    ${i}    IN RANGE    20
        ${response}=    Signed In Request    POST    /api/assistant    ${{{'mode': 'rate-limit-test'}}}
        Should Be Equal As Integers    ${response.status_code}    400
    END
    ${response}=    Signed In Request    POST    /api/assistant    ${{{'mode': 'rate-limit-test'}}}
    Should Be Equal As Integers    ${response.status_code}    429
    Should Contain    ${response.json()}[error]    resting
    Switch Context    ${MAIN_CONTEXT}
    ${other}=    Signed In Request    POST    /api/assistant    ${{{'mode': 'rate-limit-test'}}}
    Should Be Equal As Integers    ${other.status_code}    400
    ...    msg=The other player was also limited (${other.status_code}), so the limit is not per player
    [Teardown]    Remove Temporary Player

Error responses do not reveal internals
    [Documentation]    TC03-020. Expected result: error responses (invalid input,
    ...    unknown task, unknown route, malformed JSON, oversized body, disallowed
    ...    origin) contain only a short generic error message, with no stack trace,
    ...    file paths or library names.
    [Tags]    api    security
    ${today}=    Today Key
    ${responses}=    Create List
    ${r}=    Signed In Request    POST    /api/state/tasks    ${{{'key': 'walk', 'date': 'bad'}}}
    Append To List    ${responses}    ${r}
    ${r}=    Signed In Request    POST    /api/state/tasks/123/complete    ${{{'date': $today}}}
    Append To List    ${responses}    ${r}
    ${r}=    GET    ${BACKEND_URL}/api/nothing-here    expected_status=any
    Append To List    ${responses}    ${r}
    ${r}=    Signed In Raw Request    POST    /api/state/tasks    {not json
    Append To List    ${responses}    ${r}
    ${big}=    Evaluate    json.dumps({'padding': 'x' * 120000})    modules=json
    ${r}=    Signed In Raw Request    POST    /api/state/tasks    ${big}
    Append To List    ${responses}    ${r}
    ${origin}=    Create Dictionary    Origin=https://evil.example
    ${r}=    GET    ${BACKEND_URL}/api/config    headers=${origin}    expected_status=any
    Append To List    ${responses}    ${r}
    FOR    ${response}    IN    @{responses}
        Run Keyword And Continue On Failure    Response Should Not Reveal Internals    ${response}
    END

Unsupported HTTP methods return 404
    [Documentation]    TC03-021. Expected result: methods the API does not support on
    ...    its routes (PUT and PATCH, and DELETE on a collection) return 404, and the
    ...    player's game state does not change.
    [Tags]    api    security
    ${before}=    Get Game State
    FOR    ${method}    IN    PUT    PATCH
        FOR    ${path}    IN    /api/state    /api/state/tasks    /api/state/build    /api/config    /api/assistant
            ${response}=    Signed In Request    ${method}    ${path}    ${{{'totalXp': 99999}}}
            Run Keyword And Continue On Failure    Should Be Equal As Integers    ${response.status_code}    404
            ...    msg=${method} ${path} returned ${response.status_code}, expected 404
        END
    END
    ${response}=    Signed In Request    DELETE    /api/state
    Run Keyword And Continue On Failure    Should Be Equal As Integers    ${response.status_code}    404
    ${after}=    Get Game State
    Should Be Equal    ${after}[totalXp]    ${before}[totalXp]
    Should Be Equal    ${after}[missions]    ${before}[missions]


*** Keywords ***
Sign In For API Tests
    [Documentation]    Signs the standard test account in to get real session tokens
    ...    and resets its game state so every test starts from a fresh player.
    Open Test Browser
    ${main_context}=    New Context    viewport={'width': 1280, 'height': 900}
    Set Suite Variable    ${MAIN_CONTEXT}    ${main_context}
    New Page    ${APP_URL}
    Sign In
    ${user_id}=    Get Current User Id
    Set Suite Variable    ${USER_ID}    ${user_id}
    Reset Player State    ${USER_ID}

Clean Up Suite
    [Documentation]    Resets the test account's game state and closes the browser.
    Run Keyword And Ignore Error    Reset Player State    ${USER_ID}
    Close Browser

Reset Test Player
    [Documentation]    Resets the test account to a fresh player between tests.
    Reset Player State    ${USER_ID}

Request Is Rejected With 400
    [Documentation]    Sends a signed-in request and checks that the backend rejects
    ...    it with 400 and a generic error message.
    [Arguments]    ${method}    ${path}    ${body}
    ${response}=    Signed In Request    ${method}    ${path}    ${body}
    Should Be Equal As Integers    ${response.status_code}    400
    ...    msg=${method} ${path} with ${body} returned ${response.status_code}, expected 400
    Response Should Not Reveal Internals    ${response}

No Tasks Should Exist
    [Documentation]    Fails if the test account has any task, i.e. if a rejected
    ...    request still added one.
    ${state}=    Get Game State
    Should Be Empty    ${state}[missions]    msg=A rejected request still added a task: ${state}[missions]

Signed In Raw Request
    [Documentation]    Sends a request whose body is sent exactly as given (not
    ...    converted to JSON), so malformed or oversized bodies can be tested.
    [Arguments]    ${method}    ${path}    ${data}
    ${token}=    Get Session Token
    ${headers}=    Create Dictionary    Authorization=Bearer ${token}    Content-Type=application/json
    ${response}=    Run Keyword    ${method}    ${BACKEND_URL}${path}
    ...    headers=${headers}    data=${data}    expected_status=any
    RETURN    ${response}

Response Should Not Reveal Internals
    [Documentation]    Fails if the response body contains a stack trace, file path,
    ...    library name or other internal detail.
    [Arguments]    ${response}
    FOR    ${detail}    IN    @{INTERNAL_DETAILS}
        Should Not Contain    ${response.text}    ${detail}    ignore_case=True
        ...    msg=The ${response.status_code} response reveals an internal detail (${detail}): ${response.text}
    END

Clean 404 Response
    [Documentation]    Checks that the response is a 404 with only the generic
    ...    "Route not found" error.
    [Arguments]    ${response}
    Should Be Equal As Integers    ${response.status_code}    404
    Should Be Equal    ${response.json()}    ${{{'error': 'Route not found'}}}

Last Player Message Should Be
    [Documentation]    Checks the most recent player message in the conversation the
    ...    backend returned.
    [Arguments]    ${response}    ${expected}
    ${last}=    Evaluate    [m['content'] for m in $response.json()['history'] if m['role'] == 'user'][-1]
    Should Be Equal    ${last}    ${expected}

Open Companion Without Greeting
    [Documentation]    Reloads the game and opens the companion. The tab session is
    ...    first marked as already greeted, so opening does not make a greeting
    ...    OpenAI call and the chat shows only the seeded conversation.
    Reload Game
    Evaluate JavaScript    ${None}    () => sessionStorage.setItem('nimeoniter_greeted', '1')
    Click    .assistant__figure
    Wait For Elements State    .assistant__log .chat-msg >> nth=0    visible    timeout=10s

Remove Temporary Player
    [Documentation]    Deletes the temporary player of TC03-019 through the app,
    ...    removes its game state, closes its session and switches back to the
    ...    standard test account. A warning is written if the deletion fails.
    Switch Context    ${TEMP_CONTEXT}
    ${user}=    Run Keyword And Ignore Error    Get Current User Id
    ${status}    ${message}=    Run Keyword And Ignore Error    Delete Account In App
    IF    '${status}' == 'FAIL'
        Log    Deleting the temporary player failed, remove it in the Clerk dashboard: ${message}    WARN
    END
    IF    '${user}[0]' == 'PASS'
        Run Keyword And Ignore Error    Delete Player State    ${user}[1]
    END
    Close Context
    Switch Context    ${MAIN_CONTEXT}

Close Companion And Reset
    [Documentation]    Closes the companion if it is open and resets the test player.
    Run Keyword And Ignore Error    Click    .assistant__backdrop
    Reset Test Player