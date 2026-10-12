*** Settings ***
Documentation    Suite 5: Economy: XP, levels and resources.
...    Tests that the backend grants and takes back XP and resources exactly as the
...    rules say, that levels change at the right XP, that undoing a task also
...    undoes a building it paid for, and that the user interface shows the
...    backend's values. To measure task rewards exactly, the test player starts
...    with every achievement already unlocked, so no achievement reward is mixed
...    into the numbers (achievements are tested in suite 7).
...    Covers test cases TC05-001 - TC05-011.
...    Precondition: the .env test account exists in the app.
Resource    ../resources/common.robot
Suite Setup    Sign In For Economy Tests
Suite Teardown    Clean Up Suite


*** Variables ***
# One task for every combination of resources in the catalog
@{REWARD_TASKS}    walk    exercise    shop    stairs    stretch    party    outdoors


*** Test Cases ***
Completing a task grants exactly the catalog reward
    [Documentation]    TC05-001. Expected result: completing a task adds exactly the
    ...    task's catalog XP and resources and nothing else. Checked with one task
    ...    for every combination of resources in the catalog: wood, stone or food
    ...    alone, and the mixed ones.
    [Tags]    api
    Seed Economy Player
    ${today}=    Today Key
    FOR    ${key}    IN    @{REWARD_TASKS}
        ${task}=    Catalog Task    ${key}
        ${before}=    Get Game State
        ${id}=    Add Task Through API    ${key}    ${today}
        ${after}=    Complete Task Through API    ${id}    ${today}
        Run Keyword And Continue On Failure    Change Should Be    ${before}    ${after}    ${task}    1
    END
    [Teardown]    Reset Player State    ${USER_ID}

Undoing a task takes back exactly the same reward
    [Documentation]    TC05-002. Expected result: undoing a completed task takes back
    ...    exactly the XP and resources it gave, so the player is back where they
    ...    were before completing it. Checked with every resource combination.
    [Tags]    api
    Seed Economy Player    totalXp=${1000}    resources=${{ {'wood': 50, 'stone': 50, 'food': 50} }}
    ${today}=    Today Key
    FOR    ${key}    IN    @{REWARD_TASKS}
        ${task}=    Catalog Task    ${key}
        ${id}=    Add Task Through API    ${key}    ${today}
        ${before}=    Get Game State
        Complete Task Through API    ${id}    ${today}
        ${response}=    Signed In Request    POST    /api/state/tasks/${id}/uncomplete
        Should Be Equal As Integers    ${response.status_code}    200
        Run Keyword And Continue On Failure    Change Should Be    ${before}    ${response.json()}    ${task}    0
    END
    [Teardown]    Reset Player State    ${USER_ID}

XP and resources never go below zero after an undo
    [Documentation]    TC05-003. Expected result: when a completed task is undone but
    ...    the player has less XP and fewer resources than the task gave (for
    ...    example after spending them), XP and resources stop at zero instead of
    ...    going negative.
    [Tags]    api
    ${today}=    Today Key
    ${done}=    Catalog Mission    outdoors    ${today}    ${True}
    ${missions}=    Create List    ${done}
    Seed Economy Player    totalXp=${3}    missions=${missions}
    ${response}=    Signed In Request    POST    /api/state/tasks/${done}[id]/uncomplete
    Should Be Equal As Integers    ${response.status_code}    200
    Should Be Equal As Integers    ${response.json()}[totalXp]    0
    Should Be Equal    ${response.json()}[resources]    ${{ {'wood': 0, 'stone': 0, 'food': 0} }}
    [Teardown]    Reset Player State    ${USER_ID}

Levels change at the right XP
    [Documentation]    TC05-004. Expected result: level 2 starts at 100 XP, level 3 at
    ...    300 XP and level 4 at 600 XP, and one XP less stays on the lower level.
    ...    The header shows the level, and the backend agrees: the first building
    ...    (needs level 2) is refused at 99 XP and allowed at 100 XP.
    [Tags]    browser    api
    FOR    ${xp}    ${level}    IN    0    1    99    1    100    2    299    2    300    3    599    3    600    4
        Seed Economy Player    totalXp=${{int($xp)}}
        Reload Game
        Run Keyword And Continue On Failure    Get Text    .header-level-number    ==    ${level}
    END
    ${plenty}=    Create Dictionary    wood=${500}    stone=${500}    food=${500}
    Seed Economy Player    totalXp=${99}    resources=${plenty}
    ${refused}=    Signed In Request    POST    /api/state/build
    Should Be Equal As Integers    ${refused.status_code}    400
    Should Be Equal    ${refused.json()}[error]    Level too low
    Seed Economy Player    totalXp=${100}    resources=${plenty}
    ${allowed}=    Signed In Request    POST    /api/state/build
    Should Be Equal As Integers    ${allowed.status_code}    200
    [Teardown]    Reset Player State    ${USER_ID}

Level progress bar matches the backend's XP
    [Documentation]    TC05-005. Expected result: the level progress bar shows the XP
    ...    earned inside the current level and the XP the level needs, worked out
    ...    from the backend's total XP, and the bar is filled to the same share.
    ...    For example 150 XP is 50 / 200 XP into level 2, a quarter full.
    [Tags]    browser
    FOR    ${xp}    ${into}    ${needed}    ${percent}    IN    0    0    100    0    150    50    200    25    450    150    300    50
        Seed Economy Player    totalXp=${{int($xp)}}
        Reload Game
        Run Keyword And Continue On Failure    Get Text    .energy-bar-label
        ...    contains    LEVEL PROGRESS ${into} / ${needed} XP
        Run Keyword And Continue On Failure    Get Attribute    .energy-bar-fill    style
        ...    contains    width: ${percent}%
    END
    [Teardown]    Reset Player State    ${USER_ID}

Resource bar shows the backend's resources
    [Documentation]    TC05-006. Expected result: the resource bar shows exactly the
    ...    backend's wood, stone and food, and updates when they change.
    [Tags]    browser
    Seed Economy Player    resources=${{ {'wood': 12, 'stone': 345, 'food': 6789} }}
    Reload Game
    ${values}=    Get Resource Values
    Should Be Equal    ${values}    ${{['12', '345', '6789']}}
    ${today}=    Today Key
    ${id}=    Add Task Through API    party    ${today}
    Complete Task Through API    ${id}    ${today}
    Reload Game
    ${values}=    Get Resource Values
    Should Be Equal    ${values}    ${{['13', '345', '6792']}}
    [Teardown]    Reset Player State    ${USER_ID}

Level-up pop-up appears when a level is crossed
    [Documentation]    TC05-007. Expected result: when completing a task takes the
    ...    player over a level threshold (95 XP + 10 XP crosses 100), the level-up
    ...    pop-up appears with the new level and the header shows it.
    [Tags]    browser
    ${today}=    Today Key
    ${walk}=    Catalog Mission    walk    ${today}    ${False}
    ${missions}=    Create List    ${walk}
    Seed Economy Player    totalXp=${95}    missions=${missions}
    Reload Game
    Click    .mission-check >> nth=0
    # The pop-up closes itself after 2.5 seconds, so it is checked with one read
    Wait For Elements State    .levelup-overlay    visible    timeout=5s
    Get Text    .levelup-card    matches    (?s)^LEVEL UP\\s+2\\s
    Get Text    .header-level-number    ==    2
    [Teardown]    Reset Player State    ${USER_ID}

Returning player gets no level-up pop-up
    [Documentation]    TC05-008. Expected result: a player who is already on level 3
    ...    does not get a level-up pop-up when the game loads, and not after a
    ...    reload either.
    [Tags]    browser
    Seed Economy Player    totalXp=${350}
    Reload Game
    Sleep    1s
    Get Element Count    .levelup-overlay    ==    0
    Reload Game
    Sleep    1s
    Get Element Count    .levelup-overlay    ==    0
    Get Text    .header-level-number    ==    3
    [Teardown]    Reset Player State    ${USER_ID}

Undoing a task that paid for a building removes the building
    [Documentation]    TC05-009. Expected result: a task's wood completes the cost of
    ...    the well and the well is built. When the task is undone, the player can no
    ...    longer afford the well, so the well is removed and its cost is given
    ...    back. The player ends up exactly where they started, before the task and
    ...    the building.
    [Tags]    api
    ${today}=    Today Key
    ${walk}=    Catalog Mission    walk    ${today}    ${False}
    ${missions}=    Create List    ${walk}
    ${start}=    Create Dictionary    wood=${8}    stone=${5}    food=${25}
    Seed Economy Player    totalXp=${200}    resources=${start}    missions=${missions}
    Complete Task Through API    ${walk}[id]    ${today}
    ${built}=    Signed In Request    POST    /api/state/build
    Should Be Equal As Integers    ${built.status_code}    200
    Should Be Equal As Integers    ${built.json()}[baseStageIndex]    0
    Should Be Equal    ${built.json()}[resources]    ${{ {'wood': 0, 'stone': 0, 'food': 0} }}
    ${undone}=    Signed In Request    POST    /api/state/tasks/${walk}[id]/uncomplete
    Should Be Equal As Integers    ${undone.status_code}    200
    Should Be Equal As Integers    ${undone.json()}[baseStageIndex]    -1
    Should Be Equal    ${undone.json()}[resources]    ${start}
    Should Be Equal As Integers    ${undone.json()}[totalXp]    200
    [Teardown]    Reset Player State    ${USER_ID}

Undoing a task that drops the level below a building's requirement removes it
    [Documentation]    TC05-010. Expected result: a task's XP takes the player to level
    ...    2 and the well (needs level 2) is built. When the task is undone the
    ...    player drops back to level 1, so the well is removed and its cost is given
    ...    back, even though the player could still afford it.
    [Tags]    api
    ${today}=    Today Key
    ${walk}=    Catalog Mission    walk    ${today}    ${False}
    ${missions}=    Create List    ${walk}
    ${start}=    Create Dictionary    wood=${100}    stone=${100}    food=${100}
    Seed Economy Player    totalXp=${95}    resources=${start}    missions=${missions}
    Complete Task Through API    ${walk}[id]    ${today}
    ${built}=    Signed In Request    POST    /api/state/build
    Should Be Equal As Integers    ${built.status_code}    200
    ${undone}=    Signed In Request    POST    /api/state/tasks/${walk}[id]/uncomplete
    Should Be Equal As Integers    ${undone.status_code}    200
    Should Be Equal As Integers    ${undone.json()}[totalXp]    95
    Should Be Equal As Integers    ${undone.json()}[baseStageIndex]    -1
    Should Be Equal    ${undone.json()}[resources]    ${start}
    [Teardown]    Reset Player State    ${USER_ID}

Simultaneous undo, completion and build keep the state consistent
    [Documentation]    TC05-011. Expected result: when an undo, a completion and a
    ...    build are sent at exactly the same time, each request either succeeds or
    ...    is refused cleanly (an undo that loses the race returns 409), and the
    ...    final state is consistent: the XP is exactly the XP of the tasks that
    ...    ended up done, and the resources are exactly the starting resources plus
    ...    those tasks' rewards minus the cost of what was built. Repeated five
    ...    times to give the race a chance to happen.
    [Tags]    api
    ${today}=    Today Key
    FOR    ${round}    IN RANGE    5
        ${walk}=    Catalog Mission    walk    ${today}    ${True}
        ${run}=    Catalog Mission    run    ${today}    ${False}
        ${missions}=    Create List    ${walk}    ${run}
        ${start}=    Create Dictionary    wood=${10}    stone=${5}    food=${25}
        ${start_xp}=    Set Variable    ${110}
        Seed Economy Player    totalXp=${start_xp}    resources=${start}    missions=${missions}
        ${token}=    Get Session Token
        ${requests}=    Evaluate
        ...    [['POST', $BACKEND_URL + '/api/state/tasks/' + str($walk['id']) + '/uncomplete', None], ['POST', $BACKEND_URL + '/api/state/tasks/' + str($run['id']) + '/complete', {'date': $today}], ['POST', $BACKEND_URL + '/api/state/build', None]]
        ${codes}=    Send Different Requests In Parallel    ${token}    ${requests}
        Should Contain    ${{[200, 409]}}    ${codes}[0]    msg=Undo returned ${codes}[0]
        Should Contain    ${{[200, 400]}}    ${codes}[1]    msg=Completion returned ${codes}[1]
        Should Contain    ${{[200, 400]}}    ${codes}[2]    msg=Build returned ${codes}[2]
        ${state}=    Get Game State
        State Should Be Consistent    ${state}    ${start}    ${start_xp}    ${walk}    ${run}
    END
    [Teardown]    Reset Player State    ${USER_ID}


*** Keywords ***
Sign In For Economy Tests
    [Documentation]    Signs the standard test account in and loads the public game
    ...    rules (achievement ids and build stages) used by the tests.
    Open Test Browser
    Open New Session
    Sign In
    ${user_id}=    Get Current User Id
    Set Suite Variable    ${USER_ID}    ${user_id}
    ${config}=    GET    ${BACKEND_URL}/api/config
    ${ids}=    Evaluate    [a['id'] for a in $config.json()['achievements']]
    Set Suite Variable    ${ALL_ACHIEVEMENTS}    ${ids}
    Set Suite Variable    ${BUILD_STAGES}    ${config.json()}[buildStages]

Clean Up Suite
    [Documentation]    Resets the test account's game state and closes the browser.
    Run Keyword And Ignore Error    Reset Player State    ${USER_ID}
    Close Browser

Seed Economy Player
    [Documentation]    Seeds the test player with the given fields and every
    ...    achievement already unlocked, so no achievement reward changes the
    ...    numbers the test measures.
    [Arguments]    &{fields}
    Seed Player State    ${USER_ID}    unlockedAchievements=${ALL_ACHIEVEMENTS}    &{fields}

Catalog Mission
    [Documentation]    Returns a task entry for a catalog task on the given day, in the
    ...    shape the backend stores, with a unique id.
    [Arguments]    ${key}    ${date}    ${done}
    ${task}=    Catalog Task    ${key}
    ${id}=    Evaluate    random.randint(10**9, 10**10)    modules=random
    ${mission}=    Evaluate
    ...    {'id': $id, 'date': $date, 'key': $task['key'], 'name': $task['name'], 'icon': $task['icon'], 'xp': $task['xp'], 'resources': $task['resources'], 'done': $done}
    RETURN    ${mission}

Add Task Through API
    [Documentation]    Adds a task for the day and returns its id.
    [Arguments]    ${key}    ${date}
    ${body}=    Create Dictionary    key=${key}    date=${date}
    ${response}=    Signed In Request    POST    /api/state/tasks    ${body}
    Should Be Equal As Integers    ${response.status_code}    200
    ${id}=    Evaluate    [m['id'] for m in $response.json()['missions'] if m['key'] == $key and m['date'] == $date][0]
    RETURN    ${id}

Complete Task Through API
    [Documentation]    Completes a task and returns the new game state.
    [Arguments]    ${id}    ${date}
    ${body}=    Create Dictionary    date=${date}
    ${response}=    Signed In Request    POST    /api/state/tasks/${id}/complete    ${body}
    Should Be Equal As Integers    ${response.status_code}    200
    RETURN    ${response.json()}

Change Should Be
    [Documentation]    Checks that the XP and resources changed from before to after by
    ...    exactly the task's reward multiplied by times (1 = reward added,
    ...    0 = back to the same values).
    [Arguments]    ${before}    ${after}    ${task}    ${times}
    ${expected_xp}=    Evaluate    $before['totalXp'] + $task['xp'] * int($times)
    Should Be Equal As Integers    ${after}[totalXp]    ${expected_xp}
    ...    msg=${task}[key]: XP ${before}[totalXp] -> ${after}[totalXp], expected ${expected_xp}
    FOR    ${resource}    IN    wood    stone    food
        ${expected}=    Evaluate    $before['resources'][$resource] + $task['resources'].get($resource, 0) * int($times)
        Should Be Equal As Integers    ${after}[resources][${resource}]    ${expected}
        ...    msg=${task}[key]: ${resource} ${before}[resources][${resource}] -> ${after}[resources][${resource}], expected ${expected}
    END

Get Resource Values
    [Documentation]    Returns the wood, stone and food values shown in the resource bar.
    ${elements}=    Get Elements    .resource-value
    ${values}=    Create List
    FOR    ${element}    IN    @{elements}
        ${text}=    Get Text    ${element}
        Append To List    ${values}    ${text}
    END
    RETURN    ${values}

State Should Be Consistent
    [Documentation]    Recomputes the expected XP and resources from which of the two
    ...    tasks ended up done and how many stages were built, and compares them
    ...    with the actual state. The walk starts as done, so its reward is
    ...    already part of the starting values.
    [Arguments]    ${state}    ${start}    ${start_xp}    ${walk}    ${run}
    ${done}=    Evaluate    {m['id']: m['done'] for m in $state['missions']}
    ${walk_done}=    Evaluate    $done[$walk['id']]
    ${run_done}=    Evaluate    $done[$run['id']]
    ${built}=    Evaluate    $state['baseStageIndex'] + 1
    ${expected_xp}=    Evaluate
    ...    max(0, $start_xp - (0 if $walk_done else $walk['xp']) + ($run['xp'] if $run_done else 0))
    Should Be Equal As Integers    ${state}[totalXp]    ${expected_xp}
    ...    msg=Inconsistent XP after the race: ${state}
    FOR    ${resource}    IN    wood    stone    food
        ${expected}=    Evaluate
        ...    $start[$resource] - (0 if $walk_done else $walk['resources'].get($resource, 0)) + ($run['resources'].get($resource, 0) if $run_done else 0) - sum([s['cost'][$resource] for s in $BUILD_STAGES[:$built]])
        Should Be Equal As Integers    ${state}[resources][${resource}]    ${expected}
        ...    msg=Inconsistent ${resource} after the race: ${state}
        Should Be True    ${state}[resources][${resource}] >= 0
    END