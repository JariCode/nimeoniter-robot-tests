*** Settings ***
Documentation    Suite 4: Tasks.
...    Tests adding, completing, undoing and removing tasks in the browser like a
...    real player, day navigation, daily progress, the task picker and its search,
...    and the daily completion limit. Race conditions are tested against the API
...    with simultaneous requests. Every test starts from a fresh player, and game
...    states that would take too long to reach by playing (every task added, 29
...    tasks done for one day) are seeded into the test database.
...    Covers test cases TC04-001 - TC04-018.
...    Precondition: the .env test account exists in the app.
Resource    ../resources/common.robot
Suite Setup    Sign In For Task Tests
Suite Teardown    Clean Up Suite
Test Setup    Start From Fresh Player


*** Variables ***
${WALK_NAME}          Go for a walk
${RUN_NAME}           Go for a run
${DAILY_LIMIT_TEXT}   Today's quota of 30 tasks is done


*** Test Cases ***
Add task opens the task picker
    [Documentation]    TC04-001. Expected result: the "Add task" button opens the task
    ...    picker, which lists tasks with an icon, a name and the XP reward.
    [Tags]    browser
    Get Text    .add-task-button    contains    Add task
    Open Task Picker
    Get Text    .add-task-title    ==    CHOOSE A TASK
    ${count}=    Get Element Count    .add-task-option
    Should Be True    ${count} > 0
    Get Text    .add-task-option >> nth=0 >> .add-task-option-icon    !=    ${EMPTY}
    Get Text    .add-task-option >> nth=0 >> .add-task-option-name    !=    ${EMPTY}
    Get Text    .add-task-option >> nth=0 >> .add-task-option-xp    matches    ^\\+\\d+ XP$

Task picker matches the backend catalog
    [Documentation]    TC04-002. Expected result: for a player with no tasks, the task
    ...    picker lists exactly the backend's task catalog: the same number of
    ...    tasks, the same names and the same XP rewards.
    [Tags]    browser    api
    ${catalog}=    Get Task Catalog
    Open Task Picker
    ${count}=    Get Element Count    .add-task-option
    Length Should Be    ${catalog}    ${count}
    ${shown}=    Get Picker Entries
    ${expected}=    Evaluate    sorted(t['name'] + ' +' + str(t['xp']) + ' XP' for t in $catalog)
    ${shown}=    Evaluate    sorted($shown)
    Lists Should Be Equal    ${shown}    ${expected}

Search filters case-insensitively and by partial match
    [Documentation]    TC04-003. Expected result: the search keeps only tasks whose name
    ...    contains the typed text, regardless of letter case. "WALK" and "alk" both
    ...    find "Go for a walk", and every listed task contains the search text.
    [Tags]    browser
    Open Task Picker
    FOR    ${query}    IN    WALK    alk    Go For A
        Fill Text    .add-task-search    ${query}
        ${names}=    Get Picker Names
        Should Not Be Empty    ${names}
        FOR    ${name}    IN    @{names}
            Should Contain    ${name}    ${query}    ignore_case=True
        END
    END
    Fill Text    .add-task-search    WALK
    ${names}=    Get Picker Names
    Should Contain    ${names}    ${WALK_NAME}

Search with no match shows a message
    [Documentation]    TC04-004. Expected result: a search that matches no task shows
    ...    the "No tasks match" message with the search text, and no tasks.
    [Tags]    browser
    Open Task Picker
    Fill Text    .add-task-search    zzqqxx
    Get Text    .add-task-empty    ==    No tasks match "zzqqxx".
    Get Element Count    .add-task-option    ==    0

Added task appears in the day's list
    [Documentation]    TC04-005. Expected result: a task chosen in the picker appears in
    ...    the day's task list as not done, with its icon, name and XP, and it
    ...    disappears from the picker. The backend has the task for today.
    [Tags]    browser    api
    Add Task In Browser    ${WALK_NAME}
    Get Element Count    .add-task-option-name >> text="${WALK_NAME}"    ==    0
    Close Task Picker With Done
    ${row}=    Task Row    ${WALK_NAME}
    Get Text    ${row} >> .mission-check    ==    ☐
    Get Text    ${row} >> .mission-xp    ==    +10 XP
    Get Classes    ${row}    validate    'mission-done' not in value
    ${today}=    Today Key
    ${state}=    Get Game State
    ${tasks}=    Evaluate    [m for m in $state['missions'] if m['key'] == 'walk' and m['date'] == $today and not m['done']]
    Length Should Be    ${tasks}    1

Picker shows a message when every task is added
    [Documentation]    TC04-006. Expected result: when every catalog task has been
    ...    added for the day, the picker shows "All tasks added for today." and no
    ...    tasks.
    [Tags]    browser
    ${catalog}=    Get Task Catalog
    ${today}=    Today Key
    ${missions}=    Build Missions    ${catalog}    ${today}    done_count=0
    Seed Player State    ${USER_ID}    missions=${missions}
    Reload Game
    Open Task Picker
    Get Text    .add-task-empty    ==    All tasks added for today.
    Get Element Count    .add-task-option    ==    0

Every way of closing the picker works and clears the search
    [Documentation]    TC04-007. Expected result: the close button, the Done button,
    ...    clicking outside the picker and the Escape key each close the picker,
    ...    and the search is empty when the picker is opened again.
    [Tags]    browser
    FOR    ${way}    IN    close    done    outside    escape
        Open Task Picker
        Fill Text    .add-task-search    walk
        IF    '${way}' == 'close'
            Click    .add-task-close
        ELSE IF    '${way}' == 'done'
            Click    .add-task-done
        ELSE IF    '${way}' == 'outside'
            Click With Options    .add-task-overlay    left    position_x=5    position_y=5
        ELSE
            Keyboard Key    press    Escape
        END
        Wait For Elements State    .add-task-modal    detached    timeout=5s
        Open Task Picker
        Get Text    .add-task-search    ==    ${EMPTY}
        Click    .add-task-close
    END

Completing a task shows the XP and resource gain
    [Documentation]    TC04-008. Expected result: clicking the checkbox completes a
    ...    task, and clicking the task name completes another. Each shows the
    ...    floating XP reward and the resource gain, the task is marked done, and
    ...    the backend has both tasks done.
    [Tags]    browser
    Add Task In Browser    ${WALK_NAME}
    Add Task In Browser    ${RUN_NAME}
    Close Task Picker With Done
    ${walk}=    Task Row    ${WALK_NAME}
    Click    ${walk} >> .mission-check
    Wait For Elements State    ${walk} >> .mission-pop    visible    timeout=5s
    Get Text    ${walk} >> .mission-pop    ==    +10 XP
    Wait For Elements State    .resource-gain >> nth=0    visible    timeout=5s
    Wait For Elements State    ${walk} >> .mission-check >> text=☑    visible    timeout=5s
    ${run}=    Task Row    ${RUN_NAME}
    Click    ${run} >> .mission-name
    Wait For Elements State    ${run} >> .mission-pop    visible    timeout=5s
    Wait For Elements State    ${run} >> .mission-check >> text=☑    visible    timeout=5s
    ${state}=    Get Game State
    ${done}=    Evaluate    sorted(m['key'] for m in $state['missions'] if m['done'])
    Should Be Equal    ${done}    ${{['run', 'walk']}}

Clicking a completed task undoes it
    [Documentation]    TC04-009. Expected result: clicking a completed task marks it
    ...    not done again, and the backend takes back its XP and resources.
    [Tags]    browser
    Add Task In Browser    ${WALK_NAME}
    Close Task Picker With Done
    ${walk}=    Task Row    ${WALK_NAME}
    Click    ${walk} >> .mission-check
    Wait For Elements State    ${walk} >> .mission-check >> text=☑    visible    timeout=5s
    Click    ${walk} >> .mission-check
    Wait For Elements State    ${walk} >> .mission-check >> text=☐    visible    timeout=5s
    ${state}=    Get Game State
    ${task}=    Evaluate    [m for m in $state['missions'] if m['key'] == 'walk'][0]
    Should Be Equal    ${task}[done]    ${False}
    ${bonus}=    Achievement Rewards    ${state}[unlockedAchievements]
    Should Be Equal As Integers    ${state}[totalXp]    ${bonus}[xp]

Remove button removes a task that is not done
    [Documentation]    TC04-010. Expected result: the remove button removes a task that
    ...    is not done from the list and from the backend.
    [Tags]    browser
    Add Task In Browser    ${WALK_NAME}
    Close Task Picker With Done
    ${walk}=    Task Row    ${WALK_NAME}
    Click    ${walk} >> .mission-remove
    Wait For Elements State    ${walk}    detached    timeout=5s
    ${state}=    Get Game State
    Should Be Empty    ${state}[missions]

Completed task cannot be removed
    [Documentation]    TC04-011. Expected result: clicking the remove button of a
    ...    completed task does not remove it: the task stays in the list, the
    ...    backend rejects the removal (400) and keeps the task, and the player is
    ...    told why with a notice.
    [Tags]    browser    api
    Add Task In Browser    ${WALK_NAME}
    Close Task Picker With Done
    ${walk}=    Task Row    ${WALK_NAME}
    Click    ${walk} >> .mission-check
    Wait For Elements State    ${walk} >> .mission-check >> text=☑    visible    timeout=5s
    ${state}=    Get Game State
    ${id}=    Evaluate    [m['id'] for m in $state['missions'] if m['key'] == 'walk'][0]
    ${response}=    Signed In Request    DELETE    /api/state/tasks/${id}
    Should Be Equal As Integers    ${response.status_code}    400
    Click    ${walk} >> .mission-remove
    Sleep    1s
    Get Element Count    ${walk}    ==    1
    ${state}=    Get Game State
    Length Should Be    ${state}[missions]    1
    Wait For Elements State    .notice    visible    timeout=5s
    ...    message=The player is not told why the completed task was not removed

Day navigation changes the day and shows each day's own tasks
    [Documentation]    TC04-012. Expected result: the previous and next buttons move one
    ...    day at a time. Today, yesterday and tomorrow are labelled TODAY,
    ...    YESTERDAY and TOMORROW, other days have no label, and the date text is
    ...    correct for every day. A task added today is only shown on today.
    [Tags]    browser
    Add Task In Browser    ${WALK_NAME}
    Close Task Picker With Done
    ${today}=    Today Key
    Day Should Be Shown    ${today}    0    TODAY
    Click    .day-nav-arrow[aria-label="Previous day"]
    Day Should Be Shown    ${today}    -1    YESTERDAY
    Get Element Count    .mission    ==    0
    Click    .day-nav-arrow[aria-label="Previous day"]
    Day Should Be Shown    ${today}    -2    ${NONE}
    Click    .day-nav-arrow[aria-label="Next day"]
    Click    .day-nav-arrow[aria-label="Next day"]
    Day Should Be Shown    ${today}    0    TODAY
    Get Element Count    .mission    ==    1
    Click    .day-nav-arrow[aria-label="Next day"]
    Day Should Be Shown    ${today}    1    TOMORROW
    Get Element Count    .mission    ==    0
    Click    .day-nav-arrow[aria-label="Next day"]
    Day Should Be Shown    ${today}    2    ${NONE}

Tasks can be added to past and future days
    [Documentation]    TC04-013. Expected result: a task can be added on yesterday and
    ...    on tomorrow, and the backend stores each with the viewed day's date.
    [Tags]    browser    api
    ${today}=    Today Key
    Click    .day-nav-arrow[aria-label="Previous day"]
    Add Task In Browser    ${WALK_NAME}
    Close Task Picker With Done
    Click    .day-nav-arrow[aria-label="Next day"]
    Click    .day-nav-arrow[aria-label="Next day"]
    Add Task In Browser    ${RUN_NAME}
    Close Task Picker With Done
    ${yesterday}=    Shift Date    ${today}    -1
    ${tomorrow}=    Shift Date    ${today}    1
    ${state}=    Get Game State
    ${dates}=    Evaluate    {m['key']: m['date'] for m in $state['missions']}
    Should Be Equal    ${dates}[walk]    ${yesterday}
    Should Be Equal    ${dates}[run]    ${tomorrow}

Daily progress shows the viewed day's tasks and XP
    [Documentation]    TC04-014. Expected result: the daily progress shows how many of
    ...    the viewed day's tasks are done out of all of them, and the XP earned
    ...    from that day's completed tasks.
    [Tags]    browser
    Add Task In Browser    ${WALK_NAME}
    Add Task In Browser    ${RUN_NAME}
    Close Task Picker With Done
    Get Text    .daily-progress-tasks    ==    0/2 TASKS
    Get Text    .daily-progress-value    ==    ⭐ 0
    ${run}=    Task Row    ${RUN_NAME}
    Click    ${run} >> .mission-check
    Wait For Elements State    .daily-progress-tasks >> text=1/2 TASKS    visible    timeout=5s
    Get Text    .daily-progress-value    ==    ⭐ 20
    Click    .day-nav-arrow[aria-label="Previous day"]
    Get Element Count    .daily-progress-tasks    ==    0
    Get Text    .daily-progress-value    ==    ⭐ 0

Daily completion limit is enforced and undo frees a slot
    [Documentation]    TC04-015. Expected result: a player with 29 tasks done today can
    ...    complete a 30th, but the 31st is rejected: it stays not done and the
    ...    "Today's quota of 30 tasks is done" notice is shown. After one completed
    ...    task is undone, the rejected task can be completed.
    [Tags]    browser    api
    ${catalog}=    Get Task Catalog
    ${today}=    Today Key
    ${first_31}=    Evaluate    $catalog[:31]
    ${missions}=    Build Missions    ${first_31}    ${today}    done_count=29
    Seed Player State    ${USER_ID}    missions=${missions}
    Reload Game
    Get Text    .daily-progress-tasks    ==    29/31 TASKS
    ${thirtieth}=    Task Row    ${catalog}[29][name]
    Click    ${thirtieth} >> .mission-check
    Wait For Elements State    ${thirtieth} >> .mission-check >> text=☑    visible    timeout=5s
    ${thirty_first}=    Task Row    ${catalog}[30][name]
    Click    ${thirty_first} >> .mission-check
    Wait For Elements State    .notice    visible    timeout=5s
    Get Text    .notice-text    contains    ${DAILY_LIMIT_TEXT}
    Wait For Elements State    ${thirty_first} >> .mission-check >> text=☐    visible    timeout=5s
    Get Text    .daily-progress-tasks    ==    30/31 TASKS
    ${first}=    Task Row    ${catalog}[0][name]
    Click    ${first} >> .mission-check
    Wait For Elements State    ${first} >> .mission-check >> text=☐    visible    timeout=5s
    Click    ${thirty_first} >> .mission-check
    Wait For Elements State    ${thirty_first} >> .mission-check >> text=☑    visible    timeout=5s
    Get Text    .daily-progress-tasks    ==    30/31 TASKS

Tasks and their state persist over a reload
    [Documentation]    TC04-016. Expected result: after a reload, the added tasks are
    ...    still in the list and a completed task is still done.
    [Tags]    browser
    Add Task In Browser    ${WALK_NAME}
    Add Task In Browser    ${RUN_NAME}
    Close Task Picker With Done
    ${walk}=    Task Row    ${WALK_NAME}
    Click    ${walk} >> .mission-check
    Wait For Elements State    ${walk} >> .mission-check >> text=☑    visible    timeout=5s
    Reload Game
    Get Element Count    .mission    ==    2
    Get Text    ${walk} >> .mission-check    ==    ☑
    ${run}=    Task Row    ${RUN_NAME}
    Get Text    ${run} >> .mission-check    ==    ☐

Two simultaneous adds of the same task create only one
    [Documentation]    TC04-017. Expected result: when the same task is added for the
    ...    same day by two requests at exactly the same time, one succeeds (200),
    ...    the other is rejected (400), and the day has the task only once.
    [Tags]    api
    ${today}=    Today Key
    ${token}=    Get Session Token
    ${body}=    Create Dictionary    key=walk    date=${today}
    ${codes}=    Send Parallel Requests    POST    ${BACKEND_URL}/api/state/tasks    ${token}
    ...    count=2    body=${body}
    ${codes}=    Evaluate    sorted($codes)
    Should Be Equal    ${codes}    ${{[200, 400]}}
    ${state}=    Get Game State
    ${count}=    Evaluate    len([m for m in $state['missions'] if m['key'] == 'walk' and m['date'] == $today])
    Should Be Equal As Integers    ${count}    1

Two simultaneous completions of the same task grant the reward once
    [Documentation]    TC04-018. Expected result: when the same task is completed by two
    ...    requests at exactly the same time, one succeeds (200), the other is
    ...    rejected (400), and the player gets the task's XP and resources only
    ...    once (plus the rewards of achievements the backend granted).
    [Tags]    api
    ${today}=    Today Key
    ${body}=    Create Dictionary    key=walk    date=${today}
    ${added}=    Signed In Request    POST    /api/state/tasks    ${body}
    ${id}=    Evaluate    [m['id'] for m in $added.json()['missions'] if m['key'] == 'walk'][0]
    ${token}=    Get Session Token
    ${body}=    Create Dictionary    date=${today}
    ${codes}=    Send Parallel Requests    POST    ${BACKEND_URL}/api/state/tasks/${id}/complete
    ...    ${token}    count=2    body=${body}
    ${codes}=    Evaluate    sorted($codes)
    Should Be Equal    ${codes}    ${{[200, 400]}}
    ${state}=    Get Game State
    ${walk}=    Catalog Task    walk
    ${bonus}=    Achievement Rewards    ${state}[unlockedAchievements]
    ${expected_xp}=    Evaluate    $walk['xp'] + $bonus['xp']
    Should Be Equal As Integers    ${state}[totalXp]    ${expected_xp}
    ${expected_wood}=    Evaluate    $walk['resources'].get('wood', 0) + $bonus['wood']
    Should Be Equal As Integers    ${state}[resources][wood]    ${expected_wood}


*** Keywords ***
Sign In For Task Tests
    [Documentation]    Signs the standard test account in once for the whole suite.
    Open Test Browser
    Open New Session
    Sign In
    ${user_id}=    Get Current User Id
    Set Suite Variable    ${USER_ID}    ${user_id}

Clean Up Suite
    [Documentation]    Resets the test account's game state and closes the browser.
    Run Keyword And Ignore Error    Reset Player State    ${USER_ID}
    Close Browser

Start From Fresh Player
    [Documentation]    Resets the test account to a fresh player and reloads the game,
    ...    so every test starts on today with no tasks.
    Reset Player State    ${USER_ID}
    Reload Game

Open Task Picker
    [Documentation]    Opens the task picker from the "Add task" button.
    Click    .add-task-button
    Wait For Elements State    .add-task-modal    visible    timeout=5s

Close Task Picker With Done
    [Documentation]    Closes the task picker with the Done button.
    Click    .add-task-done
    Wait For Elements State    .add-task-modal    detached    timeout=5s

Add Task In Browser
    [Documentation]    Opens the task picker if it is closed, searches for the task by
    ...    name and clicks it, then waits until the task is in the day's list.
    [Arguments]    ${name}
    ${open}=    Get Element Count    .add-task-modal
    IF    ${open} == 0    Open Task Picker
    Fill Text    .add-task-search    ${name}
    Click    .add-task-option-name >> text="${name}"
    ${row}=    Task Row    ${name}
    Wait For Elements State    ${row}    visible    timeout=5s
    Fill Text    .add-task-search    ${EMPTY}

Task Row
    [Documentation]    Returns a selector for the task row with exactly this name. The
    ...    row shows the task's icon before its name, so the icon is looked up from
    ...    the catalog to match the whole text (some names are part of others, for
    ...    example "Clean" and "Clean the windows").
    [Arguments]    ${name}
    ${catalog}=    Get Task Catalog
    ${icon}=    Evaluate    [t['icon'] for t in $catalog if t['name'] == $name][0]
    RETURN    css=.mission:has(.mission-name:text-is("${icon} ${name}"))

Get Picker Names
    [Documentation]    Returns the names of the tasks currently listed in the picker.
    ${elements}=    Get Elements    .add-task-option-name
    ${names}=    Create List
    FOR    ${element}    IN    @{elements}
        ${text}=    Get Text    ${element}
        Append To List    ${names}    ${text}
    END
    RETURN    ${names}

Get Picker Entries
    [Documentation]    Returns every listed task as "name +XP XP".
    ${elements}=    Get Elements    .add-task-option
    ${entries}=    Create List
    FOR    ${element}    IN    @{elements}
        ${name}=    Get Text    ${element} >> .add-task-option-name
        ${xp}=    Get Text    ${element} >> .add-task-option-xp
        Append To List    ${entries}    ${name} ${xp}
    END
    RETURN    ${entries}

Build Missions
    [Documentation]    Returns task entries for the given catalog tasks on one day, in
    ...    the same shape the backend stores. The first done_count are done.
    [Arguments]    ${tasks}    ${date}    ${done_count}=0
    ${missions}=    Evaluate
    ...    [{'id': 1000 + i, 'date': $date, 'key': t['key'], 'name': t['name'], 'icon': t['icon'], 'xp': t['xp'], 'resources': t['resources'], 'done': i < int($done_count)} for i, t in enumerate($tasks)]
    RETURN    ${missions}

Shift Date
    [Documentation]    Returns the YYYY-MM-DD date the given number of days from date.
    [Arguments]    ${date}    ${days}
    ${shifted}=    Evaluate
    ...    (datetime.date.fromisoformat($date) + datetime.timedelta(days=int($days))).isoformat()
    ...    modules=datetime
    RETURN    ${shifted}

Day Should Be Shown
    [Documentation]    Checks the day navigation for the day the given number of days
    ...    from today: the label (or no label) and the date text, which the app
    ...    writes like "Mon, Oct 12".
    [Arguments]    ${today}    ${offset}    ${label}
    ${date}=    Shift Date    ${today}    ${offset}
    ${text}=    Evaluate
    ...    (lambda d: d.strftime('%a, %b ') + str(d.day))(datetime.date.fromisoformat($date))
    ...    modules=datetime
    Get Text    .day-nav-date    ==    ${text}
    IF    $label is None
        Get Element Count    .day-nav-label    ==    0
    ELSE
        Get Text    .day-nav-label    ==    ${label}
    END