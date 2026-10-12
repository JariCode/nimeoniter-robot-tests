*** Settings ***
Documentation    Suite 9: Living world.
...    Tests time of day, seasons, weather, space conditions and holidays in all
...    three worlds. The browser's clock is set to the date and time each check
...    needs, and the world is then drawn again (by moving the day view back and
...    forward, which needs no backend call). The page itself is always loaded
...    with the real time in a fresh browser session, because a page whose clock
...    has been changed cannot load the game again.
...    The weather and the space condition are worked out from the date and the
...    two-hour block, so the expected values below come from the app's own
...    rules: for example 14 Oct 2026 at 10:05 is a rain block.
...    Times are the computer's local time (Europe/Helsinki for these values).
...    Covers test cases TC09-001 - TC09-006 and TC09-008. TC09-007 (the look of
...    every combination) is a manual test.
...    Precondition: the .env test account exists in the app.
Resource    ../resources/common.robot
Suite Setup    Sign In For Living World Tests
Suite Teardown    Clean Up Suite


*** Variables ***
${WORLD_SVG}    .base-world-svg
# Last built stage of each world, so every building (and every decoration
# that hangs on a building) is drawn
&{WORLD_STAGE}    medieval=${7}    city=${15}    space=${23}

# The costume class each holiday puts on the companion's face. Halloween's
# skull mask has no modifier class of its own.
&{FACE_COSTUME}    halloween=.face__costume:not([class*="face__costume--"])
...    christmas=[class*="face__costume--christmas"]    newyear=[class*="face__costume--newyear"]
...    valentines=[class*="face__costume--valentines"]    easter=[class*="face__costume--easter"]


*** Test Cases ***
Time of day changes the sky and the greeting
    [Documentation]    TC09-001. Expected result: at dawn (07:00), day (13:00), dusk
    ...    (19:00) and night (23:00) the medieval sky has that time's colours (a
    ...    radial sky at night, a top-to-horizon sky otherwise) and the header
    ...    greeting reads RISE, SURVIVOR / KEEP GOING / STAY SHARP / STILL AWAKE?
    ...    In the city and in space each time of day also has its own sky.
    ...    Checked on 10 Mar 2027, a spring day without weather or holiday.
    [Tags]    browser
    Open World    medieval
    FOR    ${time}    ${greeting}    ${tag}    ${colours}    IN
    ...    07:00    RISE, SURVIVOR    linearGradient    \#3a3352 \#7a5a5e \#c8783c \#e0954a
    ...    13:00    KEEP GOING    linearGradient    \#3a5a7e \#6a88a6 \#a8b4b0
    ...    19:00    STAY SHARP    linearGradient    \#22284a \#5a3a6a \#b85a34 \#d67a3a
    ...    23:00    STILL AWAKE?    radialGradient    \#2a2418 \#16140f \#0b0a08
        Show World At    2027-03-10 ${time}:00
        Run Keyword And Continue On Failure    Get Text    .header-greeting    ==    ${greeting}
        ${sky}=    Get Sky
        Run Keyword And Continue On Failure    Should Be Equal    ${sky}    ${tag} ${colours}
        ...    msg=Wrong sky at ${time}
    END
    FOR    ${world}    IN    city    space
        Open World    ${world}
        ${skies}=    Create List
        FOR    ${time}    IN    07:00    13:00    19:00    23:00
            Show World At    2027-03-10 ${time}:00
            ${sky}=    Get Sky
            Append To List    ${skies}    ${sky}
        END
        ${different}=    Evaluate    len(set($skies))
        Run Keyword And Continue On Failure    Should Be Equal As Integers    ${different}    4
        ...    msg=The ${world} sky does not change with the time of day: ${skies}
    END

Seasons follow the month
    [Documentation]    TC09-002. Expected result: the ground colour and the season
    ...    effect follow the month: snow on the ground in winter (January), 8
    ...    flowers in spring (April), all 14 flowers in summer (July) and puddles
    ...    in autumn (October). No other season's effect is shown.
    [Tags]    browser
    Open World    medieval
    FOR    ${date}    ${ground}    ${snow}    ${flowers}    ${puddles}    IN
    ...    2027-01-14    \#565c66 \#33383f    1    0    0
    ...    2027-04-14    \#2a3018 \#161c0d    0    8    0
    ...    2027-07-15    \#2e3618 \#181f0c    0    14    0
    ...    2026-10-14    \#2a2012 \#14100a    0    0    2
        Show World At    ${date} 15:30:00
        ${colours}=    Evaluate JavaScript    ${None}
        ...    () => [...document.querySelectorAll('.base-world-svg #ground stop')].map((s) => s.getAttribute('stop-color')).join(' ')
        Run Keyword And Continue On Failure    Should Be Equal    ${colours}    ${ground}    msg=Wrong ground on ${date}
        Run Keyword And Continue On Failure    Get Element Count    ${WORLD_SVG} rect[fill="#c8d0d8"]    ==    ${snow}
        ...    message=Wrong snow cover on ${date}
        Run Keyword And Continue On Failure    Get Element Count    ${WORLD_SVG} line[stroke="#4a5a28"]    ==    ${flowers}
        ...    message=Wrong number of flowers on ${date}
        Run Keyword And Continue On Failure    Get Element Count    ${WORLD_SVG} ellipse[fill="#3a4a52"]    ==    ${puddles}
        ...    message=Wrong number of puddles on ${date}
    END

Weather stays the same within a two-hour block
    [Documentation]    TC09-003. Expected result: the weather is the same at any moment
    ...    of the same two-hour block and after drawing the world again at the
    ...    same time: rain in the 10-12 block of 14 Oct 2026 and none in its 14-16
    ...    block, snow on 9 Dec 2026 at 12-14 and thunder on 16 Jul 2027 at 8-10.
    [Tags]    browser
    Open World    medieval
    FOR    ${moment}    ${weather}    IN
    ...    2026-10-14 10:05:00    rain    2026-10-14 11:55:00    rain
    ...    2026-10-14 14:05:00    none    2026-10-14 15:55:00    none
    ...    2026-12-09 12:05:00    snow    2027-07-16 08:05:00    thunder
        FOR    ${draw}    IN RANGE    2
            Show World At    ${moment}
            ${shown}=    Get Weather
            Run Keyword And Continue On Failure    Should Be Equal    ${shown}    ${weather}
            ...    msg=Weather at ${moment} (drawing ${draw}): ${shown}, expected ${weather}
        END
    END

Holidays are active only on their dates
    [Documentation]    TC09-004. Expected result: each holiday is active from its first
    ...    to its last day and not on the day before or after: Halloween 25-31
    ...    Oct, Christmas 20-26 Dec, New Year 31 Dec - 1 Jan, Valentine's Day
    ...    11-14 Feb and Easter from Palm Sunday to Easter Monday, which moves
    ...    every year (2026: 29 Mar - 6 Apr, 2027: 21-29 Mar, 2028: 9-17 Apr).
    ...    The active holiday is read from the companion's costume.
    [Tags]    browser
    Open World    medieval
    FOR    ${date}    ${holiday}    IN
    ...    2026-10-24    none    2026-10-25    halloween    2026-10-31    halloween    2026-11-01    none
    ...    2026-12-19    none    2026-12-20    christmas    2026-12-26    christmas    2026-12-27    none
    ...    2026-12-30    none    2026-12-31    newyear    2027-01-01    newyear    2027-01-02    none
    ...    2027-02-10    none    2027-02-11    valentines    2027-02-14    valentines    2027-02-15    none
    ...    2026-03-28    none    2026-03-29    easter    2026-04-06    easter    2026-04-07    none
    ...    2027-03-20    none    2027-03-21    easter    2027-03-29    easter    2027-03-30    none
    ...    2028-04-08    none    2028-04-09    easter    2028-04-17    easter    2028-04-18    none
        Show World At    ${date} 12:00:00
        ${shown}=    Get Holiday From Costume
        Run Keyword And Continue On Failure    Should Be Equal    ${shown}    ${holiday}
        ...    msg=${date}: holiday ${shown}, expected ${holiday}
    END

Holiday decorations and costume render in every world
    [Documentation]    TC09-005. Expected result: in every world, each holiday adds its
    ...    decorations to the world and puts its costume on the companion. Each
    ...    holiday is compared with an ordinary day of the same season and time of
    ...    day without weather or space condition, so the extra elements in the
    ...    world come from the holiday alone.
    [Tags]    browser
    FOR    ${world}    IN    medieval    city    space
        Open World    ${world}
        FOR    ${holiday}    ${festive}    ${ordinary}    IN    @{HOLIDAY_PAIRS}
            Show World At    ${ordinary}
            ${plain}=    Get Element Count    ${WORLD_SVG} *
            Show World At    ${festive}
            ${decorated}=    Get Element Count    ${WORLD_SVG} *
            Run Keyword And Continue On Failure    Should Be True    ${decorated} > ${plain}
            ...    msg=No ${holiday} decorations in the ${world} world (${decorated} vs ${plain} elements)
            ${costumes}=    Get Element Count    .assistant__figure ${FACE_COSTUME}[${holiday}]
            Run Keyword And Continue On Failure    Should Be True    ${costumes} > 0
            ...    msg=The companion has no ${holiday} costume in the ${world} world
        END
    END

Space conditions replace the weather in the Space Colony
    [Documentation]    TC09-006. Expected result: in space there is never rain, snow,
    ...    thunder or clouds. Instead the space condition of the two-hour block is
    ...    shown: solar flare, meteor shower, cosmic storm, eclipse or clear. The
    ...    star field and the planet are always shown.
    [Tags]    browser
    Open World    space
    FOR    ${moment}    ${condition}    IN
    ...    2026-10-14 10:05:00    solarflare    2026-10-14 06:05:00    meteor
    ...    2026-10-14 16:05:00    cosmicstorm    2026-12-09 04:05:00    eclipse
    ...    2026-12-09 12:05:00    meteor    2026-10-14 00:05:00    clear
        Show World At    ${moment}
        ${shown}=    Get Space Condition
        Run Keyword And Continue On Failure    Should Be Equal    ${shown}    ${condition}
        ...    msg=Space condition at ${moment}: ${shown}, expected ${condition}
        ${weather}=    Get Weather
        Run Keyword And Continue On Failure    Should Be Equal    ${weather}    none
        ...    msg=Weather (${weather}) shown in space at ${moment}
        ${stars}=    Get Element Count    ${WORLD_SVG} circle.star
        Run Keyword And Continue On Failure    Should Be True    ${stars} >= 16    msg=Star field missing at ${moment}
        Run Keyword And Continue On Failure    Get Element Count    ${WORLD_SVG} circle[r="44"]    >=    2
        ...    message=Planet missing at ${moment}
    END

Holiday outfits are shown on the in-world figure in every world
    [Documentation]    TC09-008. Expected result: in every world, the figure in the
    ...    world wears something for each holiday (headwear, a mask, glasses or a
    ...    holiday-coloured outfit), so it looks different from the same figure on
    ...    an ordinary day. Exception by design: at Halloween the medieval figure
    ...    keeps its normal outfit. Halloween's costume is only a mask, and this
    ...    small figure is seen from behind at an angle, so a mask would not show.
    [Tags]    browser
    FOR    ${world}    IN    medieval    city    space
        Open World    ${world}
        FOR    ${holiday}    ${festive}    ${ordinary}    IN    @{HOLIDAY_PAIRS}
            IF    '${world}' == 'medieval' and '${holiday}' == 'halloween'    CONTINUE
            Show World At    ${ordinary}
            ${plain}=    Get Property    ${WORLD_SVG} .survivor    innerHTML
            Show World At    ${festive}
            ${dressed}=    Get Property    ${WORLD_SVG} .survivor    innerHTML
            Run Keyword And Continue On Failure    Should Not Be Equal    ${dressed}    ${plain}
            ...    msg=The figure in the ${world} world has no ${holiday} outfit
        END
    END

*** Keywords ***
Sign In For Living World Tests
    [Documentation]    Signs the standard test account in and prepares the holiday
    ...    and ordinary-day pairs. Each pair has the same season and time of day,
    ...    and neither moment has weather or a space condition.
    Open Test Browser
    Open New Session
    Sign In
    ${user_id}=    Get Current User Id
    Set Suite Variable    ${USER_ID}    ${user_id}
    # The signed-in session is saved (under browser/, which git ignores) so
    # each world can be opened in a fresh session without signing in again
    ${state}=    Save Storage State
    Set Suite Variable    ${SIGNED_IN_STATE}    ${state}
    ${config}=    GET    ${BACKEND_URL}/api/config
    ${ids}=    Evaluate    [a['id'] for a in $config.json()['achievements']]
    Set Suite Variable    ${ALL_ACHIEVEMENTS}    ${ids}
    @{pairs}=    Create List
    ...    halloween     2026-10-28 15:30:00    2026-10-14 15:30:00
    ...    christmas     2026-12-23 13:30:00    2026-12-09 11:30:00
    ...    newyear       2026-12-31 12:30:00    2026-12-09 11:30:00
    ...    valentines    2027-02-13 16:30:00    2027-02-04 16:30:00
    ...    easter        2027-03-25 15:30:00    2027-03-10 15:30:00
    Set Suite Variable    @{HOLIDAY_PAIRS}    @{pairs}

Clean Up Suite
    [Documentation]    Resets the test account's game state and closes the browser.
    Run Keyword And Ignore Error    Reset Player State    ${USER_ID}
    Close Browser

Open World
    [Documentation]    Seeds the player into the given world with every building of
    ...    that world built and every achievement unlocked, and loads the game in
    ...    a new browser session with the real time. A page cannot be reloaded
    ...    once its clock has been changed (the game never loads), so each world
    ...    gets a fresh session. The session is restored from the sign-in saved
    ...    at the start of the suite, so no new sign-in is needed.
    [Arguments]    ${world}
    Seed Player State    ${USER_ID}    totalXp=${400000}    baseStageIndex=${WORLD_STAGE}[${world}]
    ...    unlockedAchievements=${ALL_ACHIEVEMENTS}
    Close Context
    New Context    viewport={'width': 1280, 'height': 900}    storageState=${SIGNED_IN_STATE}
    New Page    ${APP_URL}
    Wait For Game To Load

Show World At
    [Documentation]    Sets the browser's clock to the given moment and draws the
    ...    world again by moving the day view one day back and forward. The world,
    ...    the header and the companion read the time again when they are drawn.
    [Arguments]    ${moment}
    Set Time    ${moment}    fixed
    Click    .day-nav-arrow[aria-label="Previous day"]
    Click    .day-nav-arrow[aria-label="Next day"]
    Sleep    0.3s

Get Sky
    [Documentation]    Returns the world's sky as "<gradient type> <colour> <colour> ...".
    ${sky}=    Evaluate JavaScript    ${None}
    ...    () => {
    ...        const sky = document.querySelector('.base-world-svg #sky');
    ...        const stops = [...sky.querySelectorAll('stop')].map((s) => s.getAttribute('stop-color'));
    ...        return [sky.tagName, ...stops].join(' ');
    ...    }
    RETURN    ${sky}

Get Weather
    [Documentation]    Returns the weather shown in the world: rain, snow, thunder or
    ...    none. Thunder also has rain drops, so lightning is checked first.
    ${lightning}=    Get Element Count    ${WORLD_SVG} .lightning-bolt
    ${snow}=    Get Element Count    ${WORLD_SVG} .snow-flake
    ${rain}=    Get Element Count    ${WORLD_SVG} .rain-drop
    IF    ${lightning} > 0    RETURN    thunder
    IF    ${snow} > 0    RETURN    snow
    IF    ${rain} > 0    RETURN    rain
    RETURN    none

Get Space Condition
    [Documentation]    Returns the space condition shown in the world: solarflare,
    ...    meteor, cosmicstorm, eclipse or clear.
    &{markers}=    Create Dictionary    solarflare=.solar-flare-pulse    meteor=.meteor-shower-streak
    ...    cosmicstorm=.cosmic-storm-pulse    eclipse=.eclipse-rim-glow
    FOR    ${condition}    ${marker}    IN    &{markers}
        ${count}=    Get Element Count    ${WORLD_SVG} ${marker}
        IF    ${count} > 0    RETURN    ${condition}
    END
    RETURN    clear

Get Holiday From Costume
    [Documentation]    Returns the holiday whose costume the companion is wearing, or
    ...    none.
    FOR    ${holiday}    ${selector}    IN    &{FACE_COSTUME}
        ${count}=    Get Element Count    .assistant__figure ${selector}
        IF    ${count} > 0    RETURN    ${holiday}
    END
    RETURN    none