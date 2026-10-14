*** Settings ***
Documentation    Suite 14: Legal documents and consent.
...    Tests that the Terms of Service and the Privacy Policy open in the app's
...    own window (modal) from every place they are linked: the landing page
...    footer, a direct /terms or /privacy address, the consent checkbox of
...    Clerk's sign-up form and the user menu. Also tests that sign-up needs
...    the consent and that the app's own sign-up page (/sign-up) works.
...    Covers test cases TC15-001 - TC15-007. TC15-008 (the consent step of a
...    Google sign-up) is manual.
...    Preconditions: the .env test account exists in the app, and "Require
...    express consent to legal documents" is on in the Clerk instance.
Resource    ../resources/common.robot
Suite Setup    Open Test Browser
Suite Teardown    Close Browser
Test Setup    Open New Session
Test Teardown    Close Session


*** Variables ***
${LEGAL_MODAL}       .legal-modal
${LEGAL_TITLE}       .legal-modal-title
${LEGAL_CLOSE}       .legal-modal-close
${LEGAL_OVERLAY}     .legal-modal-overlay
${LEGAL_BODY}        .legal-modal-body
${FOOTER_TERMS}      .landing-legal-links a >> text=Terms of Service
${FOOTER_PRIVACY}    .landing-legal-links a >> text=Privacy Policy


*** Test Cases ***
Terms of Service opens from the landing page
    [Documentation]    TC15-001. Expected result: the footer's Terms of Service link
    ...    opens the terms in a modal without leaving the page (the address does
    ...    not change). The modal is a dialog (role="dialog", aria-modal) with
    ...    the title "Terms of Service", focus moves into it and the browser tab
    ...    title changes. Escape closes it, the tab title is restored and focus
    ...    returns to the link.
    [Tags]    browser
    ${url}=    Get Url
    ${title}=    Get Title
    Click    ${FOOTER_TERMS}
    Legal Document Should Be Open    Terms of Service
    Get Attribute    ${LEGAL_MODAL}    role    ==    dialog
    Get Attribute    ${LEGAL_MODAL}    aria-modal    ==    true
    Get Title    ==    Terms of Service – Nimeoniter
    ${focus_inside}=    Evaluate JavaScript    ${None}
    ...    () => document.activeElement.closest('.legal-modal') !== null
    Should Be True    ${focus_inside}    msg=Focus did not move into the modal
    Get Url    ==    ${url}
    Keyboard Key    press    Escape
    Wait For Elements State    ${LEGAL_MODAL}    detached    timeout=5s
    Get Title    ==    ${title}
    ${focus_back}=    Evaluate JavaScript    ${FOOTER_TERMS}
    ...    (el) => el === document.activeElement
    Should Be True    ${focus_back}    msg=Focus did not return to the Terms of Service link

Privacy Policy opens from the landing page and closes in every way
    [Documentation]    TC15-002. Expected result: the footer's Privacy Policy link
    ...    opens the privacy policy in a modal. The ✕ button closes it, and
    ...    clicking outside the text (the dark background) closes it too.
    ...    Clicking the text itself does not close it.
    [Tags]    browser
    Click    ${FOOTER_PRIVACY}
    Legal Document Should Be Open    Privacy Policy
    Click    ${LEGAL_CLOSE}
    Wait For Elements State    ${LEGAL_MODAL}    detached    timeout=5s
    Click    ${FOOTER_PRIVACY}
    Legal Document Should Be Open    Privacy Policy
    Click    ${LEGAL_BODY}
    Get Element Count    ${LEGAL_MODAL}    ==    1
    Click With Options    ${LEGAL_OVERLAY}    left    position_x=5    position_y=5
    Wait For Elements State    ${LEGAL_MODAL}    detached    timeout=5s

Direct addresses open the documents
    [Documentation]    TC15-003. Expected result: opening the /terms or /privacy
    ...    address directly shows the landing page with the right document open
    ...    in the modal. When the modal is closed, the address changes back to
    ...    the app's start address.
    [Tags]    browser
    ${base}=    App Base Url
    Go To    ${base}terms
    Legal Document Should Be Open    Terms of Service
    Get Element Count    ${LANDING_BUTTON}    ==    1
    Click    ${LEGAL_CLOSE}
    Wait For Elements State    ${LEGAL_MODAL}    detached    timeout=5s
    Get Url    ==    ${base}
    Go To    ${base}privacy
    Legal Document Should Be Open    Privacy Policy
    Keyboard Key    press    Escape
    Wait For Elements State    ${LEGAL_MODAL}    detached    timeout=5s
    Get Url    ==    ${base}

Consent links open the documents over the sign-up form
    [Documentation]    TC15-004. Expected result: the sign-up form has the consent
    ...    checkbox with links to both documents. The Terms of Service link opens
    ...    the terms over the sign-up window, the text can be scrolled with the
    ...    mouse wheel, and Escape closes only the document: the sign-up form
    ...    stays open with the typed email. The Privacy Policy link works the
    ...    same way.
    [Tags]    browser
    ${email}=    Generate Test Email
    Open Sign Up Form
    Fill Text    input[name="emailAddress"]    ${email}
    Get Element Count    ${LEGAL_CHECKBOX}    ==    1
    Click    .cl-modalBackdrop a >> text=Terms of Service
    Legal Document Should Be Open    Terms of Service
    Hover    ${LEGAL_BODY}
    Mouse Wheel    0    600
    Wait Until Keyword Succeeds    5s    0.5s    Legal Text Should Be Scrolled
    Keyboard Key    press    Escape
    Wait For Elements State    ${LEGAL_MODAL}    detached    timeout=5s
    Wait For Elements State    input[name="emailAddress"]    visible    timeout=5s
    Get Text    input[name="emailAddress"]    ==    ${email}
    Click    .cl-modalBackdrop a >> text=Privacy Policy
    Legal Document Should Be Open    Privacy Policy
    Click    ${LEGAL_CLOSE}
    Wait For Elements State    ${LEGAL_MODAL}    detached    timeout=5s
    Wait For Elements State    input[name="emailAddress"]    visible    timeout=5s

Sign-up is not possible without accepting the documents
    [Documentation]    TC15-005. Expected result: when the consent checkbox is not
    ...    ticked, pressing Continue does not move on to email verification and
    ...    no account is created: the sign-up form stays open.
    [Tags]    browser
    ${email}=    Generate Test Email
    Open Sign Up Form
    Fill Text    input[name="emailAddress"]    ${email}
    Fill Text    input[name="password"]    ${TEST_PASSWORD}
    Get Checkbox State    ${LEGAL_CHECKBOX}    ==    unchecked
    Click    .cl-formButtonPrimary
    ${verification}=    Run Keyword And Return Status
    ...    Wait For Elements State    text=/Verify your email/    visible    timeout=5s
    Should Not Be True    ${verification}    msg=Sign-up went on to email verification without the consent
    Wait For Elements State    input[name="emailAddress"]    visible    timeout=5s

The app's own sign-up page works
    [Documentation]    TC15-006. Expected result: the /sign-up address shows Clerk's
    ...    sign-up form inside the app (not on Clerk's own Account Portal), with
    ...    the consent checkbox. Its "Sign in" link returns to the landing page
    ...    with the sign-in window open, and the address is the app's start
    ...    address.
    [Tags]    browser
    ${base}=    App Base Url
    Go To    ${base}sign-up
    Wait For Elements State    .cl-signUp-root    visible    timeout=15s
    Get Url    contains    /sign-up
    Get Element Count    ${LEGAL_CHECKBOX}    ==    1
    Click    .cl-footerActionLink
    Wait For Elements State    input[name="identifier"]    visible    timeout=15s
    Get Element Count    ${LANDING_BUTTON}    ==    1
    Get Url    ==    ${base}

Documents open from the user menu
    [Documentation]    TC15-007. Expected result: for a signed-in player, the user
    ...    menu has Terms of Service and Privacy Policy items between Manage
    ...    account and Sign out, and each opens its document in the modal over
    ...    the game.
    [Tags]    browser
    Sign In
    Open User Menu
    ${items}=    Get Texts    .cl-userButtonPopoverActionButton, .cl-userButtonPopoverCustomItemButton
    Should Be Equal    ${items}    ${{['Manage account', 'Terms of Service', 'Privacy Policy', 'Sign out']}}
    Click    .cl-userButtonPopoverCard >> text=Terms of Service
    Legal Document Should Be Open    Terms of Service
    Get Element Count    ${GAME_LOADED}    ==    1
    Keyboard Key    press    Escape
    Wait For Elements State    ${LEGAL_MODAL}    detached    timeout=5s
    Open User Menu
    Click    .cl-userButtonPopoverCard >> text=Privacy Policy
    Legal Document Should Be Open    Privacy Policy
    Click    ${LEGAL_CLOSE}
    Wait For Elements State    ${LEGAL_MODAL}    detached    timeout=5s


*** Keywords ***
Legal Document Should Be Open
    [Documentation]    Checks that the legal modal is open with the given title.
    [Arguments]    ${title}
    Wait For Elements State    ${LEGAL_MODAL}    visible    timeout=5s
    Get Text    ${LEGAL_TITLE}    ==    ${title}

Legal Text Should Be Scrolled
    [Documentation]    Checks that the document text has moved down from the top.
    ${top}=    Get Scroll Position    ${LEGAL_BODY}    top
    Should Be True    ${top} > 0    msg=The document text did not scroll

Open Sign Up Form
    [Documentation]    Opens the sign-in window and switches to Clerk's sign-up form.
    Open Sign In
    Click    .cl-footerActionLink
    Wait For Elements State    input[name="emailAddress"]    visible    timeout=10s

App Base Url
    [Documentation]    Returns the app's start address (APP_URL) with exactly one
    ...    slash at the end, the way the app itself writes it.
    ${base}=    Evaluate    $APP_URL.rstrip('/') + '/'
    RETURN    ${base}

Get Texts
    [Documentation]    Returns the visible texts of all elements matching the selector,
    ...    in page order.
    [Arguments]    ${selector}
    ${elements}=    Get Elements    ${selector}
    ${texts}=    Create List
    FOR    ${element}    IN    @{elements}
        ${text}=    Get Text    ${element}
        Append To List    ${texts}    ${text.strip()}
    END
    RETURN    ${texts}