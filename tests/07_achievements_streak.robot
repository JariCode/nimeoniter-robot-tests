*** Settings ***
Documentation    Suite 7: Achievements and streak.
...    Tests that achievements are granted once with their rewards, also when
...    several are earned at once or requests arrive at the same time, and that
...    the streak counts consecutive days correctly. Game states are seeded
...    straight into the test database. Each test chooses which achievements are
...    still locked; all others start as already unlocked, so only the
...    achievements under test can be granted.
...    The streak follows the date the client sends with a completion (the
...    player's own local day), so the tests send the dates they need.
...    Covers test cases TC07-001 - TC07-012.
...    Precondition: the .env test account exists in the app.
Resource    ../resources/common.robot
Suite Setup    Sign In For Achievement Tests
Suite Teardown    Clean Up Suite
Test Teardown    Reset Player State    ${USER_ID}


*** Variables ***
${MAX_XP}    ${400000}
&{PLENTY}    wood=${5000}    stone=${5000}    food=${5000}


*** Test Cases ***
First completed task shows First Step and adds its reward
    [Documentation]    TC07-001. Expected result: a new player completes their first
    ...    task in the browser. The First Step achievement pop-up appears with its
    ...    reward, and the reward is added on top of the task's own reward:
    ...    walk 10 XP + 2 wood, First Step 15 XP + 1 food.
    [Tags]    browser    api
    Reset Player State    ${USER_ID}
    Reload Game
    ${today}=    Today Key
    Add Task Through API    walk    ${today}
    Reload Game
    Click    .mission-check >> nth=0
    Wait For Elements State    .achievement    visible    timeout=5s
    Get Text    .achievement-label    ==    ACHIEVEMENT UNLOCKED
    Get Text    .achievement-title    ==    First Step
    Get Text    .achievement-reward    ==    +15 XP · 1 food
    ${state}=    Get Game State
    Should Be Equal As Integers    ${state}[totalXp]    25
    Should Be Equal    ${state}[resources]    ${{ {'wood': 2, 'stone': 0, 'food': 1} }}
    Should Be Equal    ${state}[unlockedAchievements]    ${{ ['first_task'] }}

An achievement is granted only once
    [Documentation]    TC07-002. Expected result: undoing the first task and completing
    ...    it again does not grant First Step a second time. The second completion
    ...    gives only the task's own reward and no unlocked achievements.
    [Tags]    api
    ${today}=    Today Key
    ${walk}=    Catalog Mission    walk    ${today}    ${False}
    Seed Achievement Player    first_task    missions=${{ [$walk] }}
    ${first}=    Complete Task Through API    ${walk}[id]    ${today}
    Should Be Equal    ${first}[unlockedNow]    ${{ ['first_task'] }}
    ${undone}=    Signed In Request    POST    /api/state/tasks/${walk}[id]/uncomplete
    Should Be Equal As Integers    ${undone.status_code}    200
    ${again}=    Complete Task Through API    ${walk}[id]    ${today}
    Should Be Empty    ${again}[unlockedNow]
    Should Be Equal As Integers    ${again}[totalXp]    25
    ${count}=    Evaluate    $again['unlockedAchievements'].count('first_task')
    Should Be Equal As Integers    ${count}    1

Undoing a task does not take back an achievement reward
    [Documentation]    TC07-003. Expected result: undoing the task that earned First
    ...    Step takes back only the task's own reward (10 XP, 2 wood). First Step's
    ...    reward (15 XP, 1 food) and the achievement itself stay.
    [Tags]    api
    ${today}=    Today Key
    ${walk}=    Catalog Mission    walk    ${today}    ${False}
    Seed Achievement Player    first_task    missions=${{ [$walk] }}
    Complete Task Through API    ${walk}[id]    ${today}
    ${undone}=    Signed In Request    POST    /api/state/tasks/${walk}[id]/uncomplete
    Should Be Equal As Integers    ${undone.status_code}    200
    Should Be Equal As Integers    ${undone.json()}[totalXp]    15
    Should Be Equal    ${undone.json()}[resources]    ${{ {'wood': 0, 'stone': 0, 'food': 1} }}
    Should Contain    ${undone.json()}[unlockedAchievements]    first_task

Achievement reward that crosses a level grants the level achievement too
    [Documentation]    TC07-004. Expected result: at 980 XP a walk (+10) gives 990 XP,
    ...    still level 4. First Step's reward (+15) then crosses 1000 XP, level 5,
    ...    so the level 5 achievement (Survivor) is granted in the same response.
    ...    Final XP 980 + 10 + 15 + 40 = 1045.
    [Tags]    api
    ${today}=    Today Key
    ${walk}=    Catalog Mission    walk    ${today}    ${False}
    Seed Achievement Player    first_task    level_5    totalXp=${980}    missions=${{ [$walk] }}
    ${state}=    Complete Task Through API    ${walk}[id]    ${today}
    Should Be Equal    ${state}[unlockedNow]    ${{ ['first_task', 'level_5'] }}
    Should Be Equal As Integers    ${state}[totalXp]    1045

Building achievements are granted at the right number of buildings
    [Documentation]    TC07-005. Expected result: Foundations is granted by the 1st
    ...    building, Settler by the 4th, Homestead by the 8th, Metropolis by the
    ...    16th and Fortress by the 24th (the whole base). A building in between
    ...    (the 3rd) grants nothing. Each achievement's reward is added to the
    ...    resources left after paying for the building.
    [Tags]    api
    # The 3rd building is checked with the next building achievement (Settler,
    # 4 buildings) still locked, so it must not be granted one building early.
    FOR    ${built_before}    ${locked}    ${expected}    IN    0    first_build    first_build    2    build_4    ${EMPTY}
    ...    3    build_4    build_4    7    build_8    build_8    15    build_16    build_16    23    base_complete    base_complete
        Seed Achievement Player    ${locked}    totalXp=${MAX_XP}    resources=${PLENTY}    baseStageIndex=${{int($built_before) - 1}}
        ${response}=    Signed In Request    POST    /api/state/build
        Should Be Equal As Integers    ${response.status_code}    200
        ${unlocked}=    Set Variable    ${response.json()}[unlockedNow]
        IF    $expected
            Should Be Equal    ${unlocked}    ${{ [$expected] }}    msg=Building number ${{int($built_before) + 1}} unlocked ${unlocked}
            ${stage}=    Evaluate    $BUILD_STAGES[int($built_before)]
            ${reward}=    Evaluate    $ACHIEVEMENTS[$expected]['reward']
            ${wood}=    Evaluate    $PLENTY['wood'] - $stage['cost']['wood'] + $reward['wood']
            Should Be Equal As Integers    ${response.json()}[resources][wood]    ${wood}
        ELSE
            Should Be Empty    ${unlocked}    msg=Building number ${{int($built_before) + 1}} unlocked ${unlocked}
        END
    END

Several achievements unlocked at once are shown one at a time
    [Documentation]    TC07-006. Expected result: when one completion unlocks two
    ...    achievements (First Step and, through its XP reward, Survivor), the
    ...    pop-ups are shown one after the other, never both at once: first First
    ...    Step, then Survivor.
    [Tags]    browser
    ${today}=    Today Key
    ${walk}=    Catalog Mission    walk    ${today}    ${False}
    Seed Achievement Player    first_task    level_5    totalXp=${980}    missions=${{ [$walk] }}
    Reload Game
    Click    .mission-check >> nth=0
    Wait For Elements State    .achievement-title >> text=First Step    visible    timeout=5s
    Get Element Count    .achievement    ==    1
    Wait For Elements State    .achievement-title >> text=Survivor    visible    timeout=10s
    Get Element Count    .achievement    ==    1
    Wait For Elements State    .achievement    detached    timeout=10s

Simultaneous completions do not grant an achievement twice
    [Documentation]    TC07-007. Expected result: when two different tasks are completed
    ...    at exactly the same time, both completions count but First Step is
    ...    granted only once: walk 10 XP + run 20 XP + First Step 15 XP = 45 XP.
    ...    Repeated five times to give the race a chance to happen.
    [Tags]    api
    ${today}=    Today Key
    FOR    ${round}    IN RANGE    5
        ${walk}=    Catalog Mission    walk    ${today}    ${False}
        ${run}=    Catalog Mission    run    ${today}    ${False}
        Seed Achievement Player    first_task    missions=${{ [$walk, $run] }}
        ${token}=    Get Session Token
        ${body}=    Create Dictionary    date=${today}
        ${requests}=    Evaluate
        ...    [['POST', $BACKEND_URL + '/api/state/tasks/' + str($walk['id']) + '/complete', $body], ['POST', $BACKEND_URL + '/api/state/tasks/' + str($run['id']) + '/complete', $body]]
        ${codes}=    Send Different Requests In Parallel    ${token}    ${requests}
        Should Be Equal    ${codes}    ${{ [200, 200] }}    msg=Round ${round}: statuses ${codes}
        ${state}=    Get Game State
        ${count}=    Evaluate    $state['unlockedAchievements'].count('first_task')
        Should Be Equal As Integers    ${count}    1    msg=Round ${round}: First Step granted ${count} times
        Should Be Equal As Integers    ${state}[totalXp]    45    msg=Round ${round}: XP ${state}[totalXp]
    END

Backend achievement list has display fields only
    [Documentation]    TC07-008. Expected result: the backend's public achievement list
    ...    has 24 achievements with unique ids, and each has only the display
    ...    fields id, icon, title, desc and reward. No rule logic (check
    ...    functions or thresholds) is sent to the client.
    [Tags]    api
    ${list}=    Evaluate    list($ACHIEVEMENTS.values())
    Length Should Be    ${list}    24
    Length Should Be    ${ACHIEVEMENTS}    24    msg=Achievement ids are not unique
    FOR    ${achievement}    IN    @{list}
        ${fields}=    Evaluate    sorted($achievement.keys())
        Should Be Equal    ${fields}    ${{ ['desc', 'icon', 'id', 'reward', 'title'] }}
        ...    msg=${achievement}[id] has fields ${fields}
        ${reward_fields}=    Evaluate    sorted($achievement['reward'].keys())
        Should Be Equal    ${reward_fields}    ${{ ['food', 'stone', 'wood', 'xp'] }}
    END

Streak counts consecutive days
    [Documentation]    TC07-009. Expected result: the first completion sets the streak
    ...    to 1, a second completion on the same day does not change it, a
    ...    completion on the next day adds one, and a gap of a day or more resets
    ...    it to 1. The last active date follows the completions.
    [Tags]    api
    ${today}=    Today Key
    ${missions}=    Create Missions    ${today}    walk    run    shop    exercise
    Seed Achievement Player    @{EMPTY}    missions=${missions}
    ${day1}=    Shift Date    ${today}    -10
    ${day2}=    Shift Date    ${today}    -9
    ${day4}=    Shift Date    ${today}    -7
    FOR    ${position}    ${date}    ${streak}    IN    0    ${day1}    1    1    ${day1}    1    2    ${day2}    2    3    ${day4}    1
        ${state}=    Complete Task Through API    ${missions}[${position}][id]    ${date}
        Run Keyword And Continue On Failure    Should Be Equal As Integers    ${state}[streak]    ${streak}
        ...    msg=Completion on ${date}: streak ${state}[streak], expected ${streak}
        Run Keyword And Continue On Failure    Should Be Equal    ${state}[lastActiveDate]    ${date}
    END

Header shows the streak with the right label
    [Documentation]    TC07-010. Expected result: the header shows the streak with
    ...    "DAY" for 1 and "DAYS" for more, and the streak is hidden at 0.
    [Tags]    browser
    Seed Achievement Player    @{EMPTY}    streak=${0}
    Reload Game
    Get Style    .header-streak    visibility    ==    hidden
    Seed Achievement Player    @{EMPTY}    streak=${1}
    Reload Game
    Get Style    .header-streak    visibility    ==    visible
    Get Text    .header-streak-count    ==    1
    Get Text    .header-streak-label    ==    DAY
    Seed Achievement Player    @{EMPTY}    streak=${12}
    Reload Game
    Get Text    .header-streak-count    ==    12
    Get Text    .header-streak-label    ==    DAYS

Invalid streak date is not stored
    [Documentation]    TC07-011. Expected result: a completion whose date is not in
    ...    YYYY-MM-DD format, or is an over-long string, does not store that value
    ...    as the last active date. The task may still be completed, but the last
    ...    active date stays as it was.
    [Tags]    api
    ${today}=    Today Key
    ${yesterday}=    Shift Date    ${today}    -1
    ${long}=    Evaluate    '2026-01-01' * 100
    ${missions}=    Create Missions    ${today}    walk    run    shop    exercise
    Seed Achievement Player    @{EMPTY}    missions=${missions}    streak=${4}    lastActiveDate=${yesterday}
    FOR    ${position}    ${date}    IN    0    not-a-date    1    2026-1-5    2    ${long}    3    <script>
        ${body}=    Create Dictionary    date=${date}
        Signed In Request    POST    /api/state/tasks/${missions}[${position}][id]/complete    ${body}
        ${state}=    Get Game State
        Run Keyword And Continue On Failure    Should Be Equal    ${state}[lastActiveDate]    ${yesterday}
        ...    msg=The invalid date "${date}" was stored as the last active date
    END

Streak achievements are granted at the right streaks
    [Documentation]    TC07-012. Expected result: the streak achievements are granted
    ...    when a completion takes the streak to exactly 3, 7, 14, 30, 60 and 100
    ...    days, and not one day before.
    [Tags]    api
    ${today}=    Today Key
    ${yesterday}=    Shift Date    ${today}    -1
    FOR    ${days}    IN    3    7    14    30    60    100
        FOR    ${reached}    ${expected}    IN    ${{int($days) - 1}}    ${EMPTY}    ${days}    streak_${days}
            ${walk}=    Catalog Mission    walk    ${today}    ${False}
            Seed Achievement Player    streak_${days}    missions=${{ [$walk] }}
            ...    streak=${{int($reached) - 1}}    lastActiveDate=${yesterday}
            ${state}=    Complete Task Through API    ${walk}[id]    ${today}
            Should Be Equal As Integers    ${state}[streak]    ${reached}
            IF    $expected
                Should Be Equal    ${state}[unlockedNow]    ${{ [$expected] }}
                ...    msg=Streak ${reached} unlocked ${state}[unlockedNow]
            ELSE
                Should Be Empty    ${state}[unlockedNow]    msg=Streak ${reached} unlocked ${state}[unlockedNow]
            END
        END
    END


*** Keywords ***
Sign In For Achievement Tests
    [Documentation]    Signs the standard test account in and loads the public game
    ...    rules (achievements by id and build stages) used by the tests.
    Open Test Browser
    Open New Session
    Sign In
    ${user_id}=    Get Current User Id
    Set Suite Variable    ${USER_ID}    ${user_id}
    ${config}=    GET    ${BACKEND_URL}/api/config
    ${achievements}=    Evaluate    {a['id']: a for a in $config.json()['achievements']}
    Set Suite Variable    ${ACHIEVEMENTS}    ${achievements}
    Set Suite Variable    ${BUILD_STAGES}    ${config.json()}[buildStages]

Clean Up Suite
    [Documentation]    Resets the test account's game state and closes the browser.
    Run Keyword And Ignore Error    Reset Player State    ${USER_ID}
    Close Browser

Seed Achievement Player
    [Documentation]    Seeds the test player with the given fields. The listed
    ...    achievement ids stay locked; every other achievement starts as already
    ...    unlocked, so only the listed ones can be granted. Use @{EMPTY} to
    ...    unlock everything.
    [Arguments]    @{locked}    &{fields}
    ${unlocked}=    Evaluate    [a for a in $ACHIEVEMENTS if a not in $locked]
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

Create Missions
    [Documentation]    Returns not-done task entries for the given catalog keys on the
    ...    given day.
    [Arguments]    ${date}    @{keys}
    ${missions}=    Create List
    FOR    ${key}    IN    @{keys}
        ${mission}=    Catalog Mission    ${key}    ${date}    ${False}
        Append To List    ${missions}    ${mission}
    END
    RETURN    ${missions}

Add Task Through API
    [Documentation]    Adds a task for the day and returns its id.
    [Arguments]    ${key}    ${date}
    ${body}=    Create Dictionary    key=${key}    date=${date}
    ${response}=    Signed In Request    POST    /api/state/tasks    ${body}
    Should Be Equal As Integers    ${response.status_code}    200
    ${id}=    Evaluate    [m['id'] for m in $response.json()['missions'] if m['key'] == $key and m['date'] == $date][0]
    RETURN    ${id}

Complete Task Through API
    [Documentation]    Completes a task with the given streak date and returns the new
    ...    game state, including unlockedNow.
    [Arguments]    ${id}    ${date}
    ${body}=    Create Dictionary    date=${date}
    ${response}=    Signed In Request    POST    /api/state/tasks/${id}/complete    ${body}
    Should Be Equal As Integers    ${response.status_code}    200
    RETURN    ${response.json()}

Shift Date
    [Documentation]    Returns the YYYY-MM-DD date the given number of days from date.
    [Arguments]    ${date}    ${days}
    ${shifted}=    Evaluate
    ...    (datetime.date.fromisoformat($date) + datetime.timedelta(days=int($days))).isoformat()
    ...    modules=datetime
    RETURN    ${shifted}