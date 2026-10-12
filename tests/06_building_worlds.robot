*** Settings ***
Documentation    Suite 6: Building and world progression.
...    Tests the build panel, building in all three worlds, the backend's build
...    rules, the world changes (Medieval/Wilderness -> Modern City -> Space
...    Colony) and World Complete. Game states are seeded straight into the test
...    database, so any stage of the game can be tested without playing up to it.
...    The test player starts with every achievement already unlocked, so no
...    achievement pop-up covers the world and no achievement reward changes the
...    resources the tests measure (achievements are tested in suite 7).
...    Covers test cases TC06-001 - TC06-012 and TC06-014. TC06-013 (the look of
...    all 24 buildings) is a manual test.
...    Precondition: the .env test account exists in the app.
Resource    ../resources/common.robot
Suite Setup    Sign In For Building Tests
Suite Teardown    Clean Up Suite
Test Teardown    Reset Player State    ${USER_ID}


*** Variables ***
# Enough XP for every level requirement (level 80 needs 316 000 XP) and
# enough resources for any single building
${MAX_XP}    ${400000}
&{PLENTY}    wood=${5000}    stone=${5000}    food=${5000}

# Elements that show which world is on screen. The NIMEONITER sign in the
# world is a wooden board in the medieval world, a neon marquee in the city
# and a hologram in space. The companion wears a green jacket in the medieval
# world, a black coat in the city and a white spacesuit in space. The jacket is
# checked because it is drawn in every world (in space the helmet replaces the hood).
${MEDIEVAL_SIGN}       css=.base-world-svg text[fill="#d9b06a"]
${CITY_NEON_SIGN}      css=.base-world-svg text.neon-pulse[stroke="#ff3d9a"]
${SPACE_HOLOGRAM}      css=.base-world-svg text[stroke="#8fe0ff"]
${MEDIEVAL_OUTFIT}     css=.assistant__figure [fill="url(#jacket)"]
${CITY_OUTFIT}         css=.assistant__figure [fill="url(#jacketCity)"]
${SPACE_OUTFIT}        css=.assistant__figure [fill="url(#jacketSpace)"]

@{STAGE_ORDER}    well    hut    house    field    storage    fence    watchtower    wall
...    street    apartment    diner    shop    hotel    casino    theater    skyscraper
...    landing-pad    habitat    greenhouse    solar-array    comms-tower    lab    reactor    command-tower


*** Test Cases ***
Next building and its cost are shown with colours
    [Documentation]    TC06-001. Expected result: the build panel shows the next
    ...    building's name and each of its costs as "have/needed". A cost the
    ...    player can pay is shown in the "enough" colour (cost-ok) and a cost
    ...    they cannot pay in the "missing" colour (cost-missing).
    [Tags]    browser
    ${resources}=    Create Dictionary    wood=${10}    stone=${4}    food=${30}
    Seed Builder Player    totalXp=${100}    resources=${resources}
    Reload Game
    Get Text    .base-build-label    ==    NEXT: WELL
    Cost Should Be    0    🪵 10/10    cost-ok
    Cost Should Be    1    🪨 4/5    cost-missing
    Cost Should Be    2    🍖 30/25    cost-ok

Build button is disabled when resources are short
    [Documentation]    TC06-002. Expected result: when the level is high enough but
    ...    a resource is short, the build button is disabled and reads
    ...    "NOT ENOUGH RESOURCES".
    [Tags]    browser
    ${resources}=    Create Dictionary    wood=${10}    stone=${4}    food=${25}
    Seed Builder Player    totalXp=${100}    resources=${resources}
    Reload Game
    Get Text    .base-build-button    ==    NOT ENOUGH RESOURCES
    Get Element States    .base-build-button    contains    disabled

Build button asks for a higher level when the level is too low
    [Documentation]    TC06-003. Expected result: when the player has the resources
    ...    but too low a level, the build button is disabled and reads
    ...    "REACH LEVEL X TO BUILD" with the next building's level requirement.
    ...    Checked for the well (level 2) and the hut (level 3).
    [Tags]    browser
    Seed Builder Player    totalXp=${99}    resources=${PLENTY}
    Reload Game
    Get Text    .base-build-button    ==    REACH LEVEL 2 TO BUILD
    Get Element States    .base-build-button    contains    disabled
    Seed Builder Player    totalXp=${299}    resources=${PLENTY}    baseStageIndex=${0}
    Reload Game
    Get Text    .base-build-label    ==    NEXT: HUT
    Get Text    .base-build-button    ==    REACH LEVEL 3 TO BUILD
    Get Element States    .base-build-button    contains    disabled

Building deducts the cost and adds the building to the world
    [Documentation]    TC06-004. Expected result: when the level and resources are
    ...    enough, the button reads "BUILD WELL". Building takes exactly the
    ...    well's cost, moves the base one stage forward, draws the well in the
    ...    world and moves the panel on to the next building.
    [Tags]    browser    api
    ${resources}=    Create Dictionary    wood=${15}    stone=${10}    food=${30}
    Seed Builder Player    totalXp=${100}    resources=${resources}
    Reload Game
    Get Text    .base-world-stage    ==    CAMP
    ${shapes_before}=    Get Element Count    .base-world-svg *
    Get Text    .base-build-button    ==    BUILD WELL
    Click    .base-build-button
    Get Text    .base-world-stage    ==    WELL
    Get Text    .base-build-label    ==    NEXT: HUT
    ${shapes_after}=    Get Element Count    .base-world-svg *
    Should Be True    ${shapes_after} > ${shapes_before}    msg=The well was not drawn in the world
    ${state}=    Get Game State
    Should Be Equal As Integers    ${state}[baseStageIndex]    0
    Should Be Equal    ${state}[resources]    ${{ {'wood': 5, 'stone': 5, 'food': 5} }}

Backend rejects a build without the level or the resources
    [Documentation]    TC06-005. Expected result: the backend refuses a build when the
    ...    level is too low ("Level too low") or a resource is short ("Not enough
    ...    resources"), even when the request is sent straight to the API past
    ...    the disabled button, and the game state stays exactly the same.
    [Tags]    api
    Seed Builder Player    totalXp=${99}    resources=${PLENTY}
    Build Should Be Refused    Level too low
    ${short}=    Create Dictionary    wood=${10}    stone=${5}    food=${24}
    Seed Builder Player    totalXp=${100}    resources=${short}
    Build Should Be Refused    Not enough resources

Stages cannot be skipped
    [Documentation]    TC06-006. Expected result: a build always takes the next stage
    ...    in order and pays only its cost. A request that asks for a later stage
    ...    (here the wall) is ignored: with the house built, the field is built.
    [Tags]    api
    Seed Builder Player    totalXp=${MAX_XP}    resources=${PLENTY}    baseStageIndex=${2}
    ${body}=    Create Dictionary    key=wall    stage=wall    stageIndex=${7}    baseStageIndex=${7}
    ${response}=    Signed In Request    POST    /api/state/build    ${body}
    Should Be Equal As Integers    ${response.status_code}    200
    Should Be Equal As Integers    ${response.json()}[baseStageIndex]    3
    ${field}=    Evaluate    $BUILD_STAGES[3]
    Should Be Equal    ${field}[key]    field
    FOR    ${resource}    IN    wood    stone    food
        ${expected}=    Evaluate    $PLENTY[$resource] - $field['cost'][$resource]
        Should Be Equal As Integers    ${response.json()}[resources][${resource}]    ${expected}
    END

Two simultaneous builds pay the cost only once
    [Documentation]    TC06-007. Expected result: when two build requests are sent at
    ...    exactly the same time with resources for exactly one well, only one
    ...    succeeds (200) and the other is refused (400). The well is built once
    ...    and its cost is paid once. Repeated five times to give the race a
    ...    chance to happen.
    [Tags]    api
    FOR    ${round}    IN RANGE    5
        ${resources}=    Create Dictionary    wood=${10}    stone=${5}    food=${25}
        Seed Builder Player    totalXp=${1000}    resources=${resources}
        ${token}=    Get Session Token
        ${codes}=    Send Parallel Requests    POST    ${BACKEND_URL}/api/state/build    ${token}    2
        ${codes}=    Evaluate    sorted($codes)
        Should Be Equal    ${codes}    ${{[200, 400]}}    msg=Round ${round}: statuses ${codes}
        ${state}=    Get Game State
        Should Be Equal As Integers    ${state}[baseStageIndex]    0
        Should Be Equal    ${state}[resources]    ${{ {'wood': 0, 'stone': 0, 'food': 0} }}
    END

Building the street changes the world to the Modern City
    [Documentation]    TC06-008. Expected result: before the street the world is the
    ...    medieval one (wooden sign, companion in the green hood). Building the
    ...    first city stage (Street) changes the world to the Modern City: the
    ...    city scene with the street is drawn, the wooden sign is replaced by the
    ...    neon sign and the companion changes into the city outfit.
    [Tags]    browser
    Seed Builder Player    totalXp=${MAX_XP}    resources=${PLENTY}    baseStageIndex=${7}
    Reload Game
    World Should Be    medieval
    Get Text    .base-build-label    ==    NEXT: STREET
    Click    .base-build-button
    Get Text    .base-world-stage    ==    STREET
    World Should Be    city

Building the landing pad changes the world to the Space Colony
    [Documentation]    TC06-009. Expected result: building the first space stage
    ...    (Landing Pad) changes the world from the Modern City to the Space
    ...    Colony: the neon sign is replaced by the hologram and the companion
    ...    changes into the spacesuit.
    [Tags]    browser
    Seed Builder Player    totalXp=${MAX_XP}    resources=${PLENTY}    baseStageIndex=${15}
    Reload Game
    World Should Be    city
    Get Text    .base-build-label    ==    NEXT: LANDING PAD
    Click    .base-build-button
    Get Text    .base-world-stage    ==    LANDING-PAD
    World Should Be    space

World Complete is shown once when a world's last stage is built
    [Documentation]    TC06-010. Expected result: building the last stage of each
    ...    world (Wall, Skyscraper and Command Tower) shows World Complete. It
    ...    closes by itself, and it does not appear again after a reload.
    ...    The world does not change on its own: the finished world stays on
    ...    screen until the player builds the next world's first stage.
    [Tags]    browser
    FOR    ${index}    ${stage}    ${world}    IN    7    WALL    medieval    15    SKYSCRAPER    city    23    COMMAND-TOWER    space
        Seed Builder Player    totalXp=${MAX_XP}    resources=${PLENTY}    baseStageIndex=${{int($index) - 1}}
        Reload Game
        Get Element Count    .worldcomplete-overlay    ==    0
        Click    .base-build-button
        Wait For Elements State    .worldcomplete-overlay    visible    timeout=5s
        Get Text    .worldcomplete-label    ==    WORLD COMPLETE
        Get Text    .base-world-stage    ==    ${stage}
        Wait For Elements State    .worldcomplete-overlay    detached    timeout=10s
        World Should Be    ${world}
        Reload Game
        Sleep    1s
        Get Element Count    .worldcomplete-overlay    ==    0
    END

Fully built base shows the message and refuses more builds
    [Documentation]    TC06-011. Expected result: after the final stage the build
    ...    panel is replaced by "Your base is fully built." with no build button,
    ...    and the backend refuses any further build ("Base fully built") without
    ...    changing the game state.
    [Tags]    browser    api
    Seed Builder Player    totalXp=${MAX_XP}    resources=${PLENTY}    baseStageIndex=${23}
    Reload Game
    Get Text    .base-build-complete    ==    Your base is fully built.
    Get Element Count    .base-build-button    ==    0
    Build Should Be Refused    Base fully built

Reload shows the right world straight away
    [Documentation]    TC06-012. Expected result: when a city or space player
    ...    reloads the page, the medieval world never flashes on screen before
    ...    the real one: no wooden sign, no CAMP stage and no green hood appear
    ...    at any moment while the page loads. A watcher is started in the page
    ...    as soon as the new page exists and records anything medieval it sees.
    [Tags]    browser
    FOR    ${index}    ${world}    IN    10    city    20    space
        Seed Builder Player    totalXp=${MAX_XP}    resources=${PLENTY}    baseStageIndex=${{int($index)}}
        Reload    waitUntil=commit
        Start Wrong World Watcher
        Wait For Game To Load
        Wait For Elements State    css=.assistant__figure    visible    timeout=10s
        ${seen}=    Evaluate JavaScript    ${None}    () => window.__wrongWorldSeen
        Should Not Be Equal    ${seen}    ${None}    msg=The watcher was not running during the reload
        Should Be Empty    ${seen}    msg=The medieval world flashed before the ${world} world: ${seen}
        World Should Be    ${world}
    END

Backend build list has 24 stages in the right order
    [Documentation]    TC06-014. Expected result: the backend's public build list
    ...    has 24 stages in the planned order, 8 for each world, the worlds in the
    ...    order Medieval -> City -> Space, and each stage needs a higher level
    ...    than the one before it.
    [Tags]    api
    Length Should Be    ${BUILD_STAGES}    24
    ${keys}=    Evaluate    [s['key'] for s in $BUILD_STAGES]
    Lists Should Be Equal    ${keys}    ${STAGE_ORDER}
    ${worlds}=    Evaluate    [s['world'] for s in $BUILD_STAGES]
    ${expected_worlds}=    Evaluate    ['medieval'] * 8 + ['city'] * 8 + ['space'] * 8
    Lists Should Be Equal    ${worlds}    ${expected_worlds}
    ${levels}=    Evaluate    [s['requiredLevel'] for s in $BUILD_STAGES]
    ${rising}=    Evaluate    all(a < b for a, b in zip($levels, $levels[1:]))
    Should Be True    ${rising}    msg=Level requirements do not rise: ${levels}


*** Keywords ***
Sign In For Building Tests
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

Seed Builder Player
    [Documentation]    Seeds the test player with the given fields and every
    ...    achievement already unlocked, so no achievement pop-up or reward gets
    ...    in the way of the building tests.
    [Arguments]    &{fields}
    Seed Player State    ${USER_ID}    unlockedAchievements=${ALL_ACHIEVEMENTS}    &{fields}

Cost Should Be
    [Documentation]    Checks the text and colour class of one cost in the build panel.
    ...    The costs are shown in the order wood, stone, food.
    [Arguments]    ${position}    ${text}    ${colour_class}
    ${cost}=    Set Variable    css=.base-build-cost span >> nth=${position}
    Get Text    ${cost}    ==    ${text}
    Get Classes    ${cost}    contains    ${colour_class}

Build Should Be Refused
    [Documentation]    Sends a build request straight to the API and checks that it is
    ...    refused with the given error and that the game state does not change.
    [Arguments]    ${error}
    ${before}=    Get Game State
    ${response}=    Signed In Request    POST    /api/state/build
    Should Be Equal As Integers    ${response.status_code}    400
    Should Be Equal    ${response.json()}[error]    ${error}
    ${after}=    Get Game State
    FOR    ${field}    IN    totalXp    resources    baseStageIndex    missions
        Should Be Equal    ${after}[${field}]    ${before}[${field}]
        ...    msg=${field} changed: ${before}[${field}] -> ${after}[${field}]
    END

World Should Be
    [Documentation]    Checks that the given world is on screen and the other worlds
    ...    are not: the world's own NIMEONITER sign and the companion's outfit
    ...    for that world.
    [Arguments]    ${world}
    &{signs}=    Create Dictionary    medieval=${MEDIEVAL_SIGN}    city=${CITY_NEON_SIGN}    space=${SPACE_HOLOGRAM}
    &{outfits}=    Create Dictionary    medieval=${MEDIEVAL_OUTFIT}    city=${CITY_OUTFIT}    space=${SPACE_OUTFIT}
    FOR    ${name}    IN    medieval    city    space
        ${expected}=    Set Variable If    '${name}' == '${world}'    ${1}    ${0}
        Run Keyword And Continue On Failure    Get Element Count    ${signs}[${name}]    ==    ${expected}
        ...    message=Wrong number of ${name} signs in the ${world} world
        ${outfit}=    Get Element Count    ${outfits}[${name}]
        IF    '${name}' == '${world}'
            Run Keyword And Continue On Failure    Should Be True    ${outfit} > 0
            ...    msg=The companion is not wearing the ${world} outfit
        ELSE
            Run Keyword And Continue On Failure    Should Be Equal As Integers    ${outfit}    0
            ...    msg=The companion is wearing the ${name} outfit in the ${world} world
        END
    END

Start Wrong World Watcher
    [Documentation]    Starts a watcher in the page that records every moment the
    ...    medieval world shows up while the page loads: the wooden sign, the
    ...    CAMP stage text or the companion's green hood. The findings are read
    ...    from window.__wrongWorldSeen once the game has loaded.
    Evaluate JavaScript    ${None}
    ...    () => {
    ...        window.__wrongWorldSeen = [];
    ...        const seen = window.__wrongWorldSeen;
    ...        const note = (what) => { if (!seen.includes(what)) seen.push(what); };
    ...        const check = () => {
    ...            if (document.querySelector('.base-world-svg text[fill="#d9b06a"]')) note('wooden sign');
    ...            const stage = document.querySelector('.base-world-stage');
    ...            if (stage && stage.textContent === 'CAMP') note('CAMP stage');
    ...            if (document.querySelector('.assistant__figure [fill="url(#jacket)"]')) note('green jacket');
    ...        };
    ...        new MutationObserver(check).observe(document, { childList: true, subtree: true, attributes: true });
    ...        check();
    ...    }