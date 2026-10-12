*** Settings ***
Documentation    Suite 13: Security configuration.
...    Tests the security headers of the backend and of the frontend production
...    build (vite preview), the .htaccess file generated for the Apache
...    production host, CORS, that no secrets are built into the code sent to
...    browsers, that the health route reveals nothing about the technology,
...    and that every asset loads under the deployment sub-path.
...    The .htaccess test reads the file from the frontend build folder given as
...    FRONTEND_DIST in the .env file (for example C:/.../nimeoniter/frontend/dist).
...    Covers test cases TC13-001 - TC13-007.
...    Precondition: the frontend has been built (npm run build) with the same
...    .env as the running preview, and the .env test account exists.
Resource    ../resources/common.robot
Library    OperatingSystem
Suite Setup    Sign In For Security Tests
Suite Teardown    Clean Up Suite


*** Variables ***
${ALLOWED_ORIGIN}       http://localhost:4173
${FORBIDDEN_ORIGIN}     https://evil.example.com

# Headers every backend response must carry: name and a part of the value
&{BACKEND_HEADERS}
...    Content-Security-Policy=default-src 'none'
...    Strict-Transport-Security=max-age=
...    X-Content-Type-Options=nosniff
...    X-Frame-Options=DENY
...    Referrer-Policy=no-referrer
...    Cross-Origin-Resource-Policy=same-site
...    Cross-Origin-Opener-Policy=same-origin
...    Permissions-Policy=camera=()
...    Cache-Control=no-store

# Headers the frontend build must carry: name and a part of the value
&{FRONTEND_HEADERS}
...    Content-Security-Policy=default-src 'self'
...    Strict-Transport-Security=max-age=
...    X-Content-Type-Options=nosniff
...    X-Frame-Options=DENY
...    Referrer-Policy=strict-origin-when-cross-origin
...    Permissions-Policy=camera=()
...    Cross-Origin-Opener-Policy=same-origin
...    Cross-Origin-Resource-Policy=same-origin


*** Test Cases ***
Every backend response carries the security headers
    [Documentation]    TC13-001. Expected result: every kind of backend response
    ...    (health route, public route, signed-in route, refused request without
    ...    a token and unknown route) carries the security headers: CSP
    ...    default-src 'none', HSTS, nosniff, X-Frame-Options DENY, Referrer-Policy
    ...    no-referrer, Cross-Origin-Resource-Policy, Cross-Origin-Opener-Policy,
    ...    Permissions-Policy and Cache-Control no-store, and no X-Powered-By.
    [Tags]    api    security
    ${token}=    Get Session Token
    ${signed_in}=    Create Dictionary    Authorization=Bearer ${token}
    FOR    ${path}    ${headers}    IN
    ...    /    ${None}
    ...    /api/config    ${None}
    ...    /api/state    ${signed_in}
    ...    /api/state    ${None}
    ...    /api/no-such-route    ${None}
        ${response}=    GET    ${BACKEND_URL}${path}    headers=${headers}    expected_status=any
        Run Keyword And Continue On Failure    Headers Should Contain    ${response}    ${BACKEND_HEADERS}
        ...    backend ${path} (${response.status_code})
        Run Keyword And Continue On Failure    Dictionary Should Not Contain Key    ${response.headers}    X-Powered-By
        ...    msg=backend ${path} reveals X-Powered-By
    END

Frontend build carries the security headers
    [Documentation]    TC13-002. Expected result: the frontend production build
    ...    (the page and its assets) carries the security headers: Content
    ...    Security Policy, HSTS, nosniff, X-Frame-Options DENY, Referrer-Policy,
    ...    Permissions-Policy, Cross-Origin-Opener-Policy and
    ...    Cross-Origin-Resource-Policy. The CSP also blocks plugins and framing.
    [Tags]    api    security
    ${files}=    Crawl Frontend Build    ${APP_URL}
    ${script}=    Evaluate    [f['url'] for f in $files if f['url'].endswith('.js') and f['status'] == 200][0]
    FOR    ${url}    IN    ${APP_URL}    ${script}
        ${response}=    GET    ${url}    expected_status=any
        Run Keyword And Continue On Failure    Headers Should Contain    ${response}    ${FRONTEND_HEADERS}    ${url}
    END
    ${page}=    GET    ${APP_URL}
    ${csp}=    Set Variable    ${page.headers}[Content-Security-Policy]
    FOR    ${directive}    IN    object-src 'none'    frame-ancestors 'none'    base-uri 'self'
        Run Keyword And Continue On Failure    Should Contain    ${csp}    ${directive}
        ...    msg=The frontend CSP has no ${directive}: ${csp}
    END

Generated .htaccess has the routing rule and the same headers
    [Documentation]    TC13-003. Expected result: the .htaccess file in the frontend
    ...    build has the routing rule for the deployment sub-path (every unknown
    ...    path under it is served by index.html) and sets exactly the same
    ...    security headers, with the same values, as the preview server.
    [Tags]    api    security
    Should Not Be Empty    ${FRONTEND_DIST}    msg=Set FRONTEND_DIST in the .env file to the frontend build folder
    ${htaccess}=    Get File    ${FRONTEND_DIST}/.htaccess    encoding=UTF-8
    ${base}=    Evaluate    urllib.parse.urlparse($APP_URL).path    modules=urllib.parse
    Should Contain    ${htaccess}    RewriteBase ${base}
    Should Contain    ${htaccess}    RewriteRule . ${base}index.html [L]
    ${page}=    GET    ${APP_URL}
    FOR    ${name}    IN    @{FRONTEND_HEADERS}
        ${value}=    Set Variable    ${page.headers}[${name}]
        Run Keyword And Continue On Failure    Should Contain    ${htaccess}    Header always set ${name} "${value}"
        ...    msg=.htaccess does not set ${name} to the preview's value "${value}"
    END

CORS allows only the configured origins
    [Documentation]    TC13-004. Expected result: a request from an allowed origin
    ...    gets the Access-Control-Allow-Origin header with that origin. A request
    ...    from a disallowed origin gets no Access-Control-Allow-Origin header and
    ...    is refused without a server error (no 500).
    [Tags]    api    security
    ${allowed}=    Create Dictionary    Origin=${ALLOWED_ORIGIN}
    ${response}=    GET    ${BACKEND_URL}/api/config    headers=${allowed}    expected_status=any
    Should Be Equal As Integers    ${response.status_code}    200
    Should Be Equal    ${response.headers}[Access-Control-Allow-Origin]    ${ALLOWED_ORIGIN}
    ${forbidden}=    Create Dictionary    Origin=${FORBIDDEN_ORIGIN}
    ${response}=    GET    ${BACKEND_URL}/api/config    headers=${forbidden}    expected_status=any
    Run Keyword And Continue On Failure    Dictionary Should Not Contain Key    ${response.headers}    Access-Control-Allow-Origin
    ...    msg=A disallowed origin got an Access-Control-Allow-Origin header
    Run Keyword And Continue On Failure    Should Be True    ${response.status_code} < 500
    ...    msg=A disallowed origin caused a server error (${response.status_code})

No secrets are built into the frontend
    [Documentation]    TC13-005. Expected result: none of the files sent to the
    ...    browser (the page and every script and stylesheet it loads) contains an
    ...    OpenAI key, a Clerk secret key or webhook signing secret, a MongoDB
    ...    connection string or the backend's secret variable names. The Clerk
    ...    publishable key (pk_) is public by design and is allowed.
    [Tags]    api    security
    ${files}=    Crawl Frontend Build    ${APP_URL}
    ${scripts}=    Evaluate    [f['url'] for f in $files if f['url'].endswith('.js') and f['status'] == 200]
    Should Not Be Empty    ${scripts}    msg=No scripts were found to check
    ${secrets}=    Find Secrets    ${files}
    Should Be Empty    ${secrets}    msg=Secrets in the frontend build: ${secrets}

Health route reveals no technology information
    [Documentation]    TC13-006. Expected result: the backend's health route answers
    ...    with a plain status and reveals no version numbers, frameworks or
    ...    server software, neither in the body nor in the headers.
    [Tags]    api    security
    ${response}=    GET    ${BACKEND_URL}/
    ${body}=    Convert To Lower Case    ${response.text}
    FOR    ${word}    IN    express    node    version    mongo    mongoose    helmet    clerk    openai
        Run Keyword And Continue On Failure    Should Not Contain    ${body}    ${word}
        ...    msg=The health route mentions "${word}": ${response.text}
    END
    Run Keyword And Continue On Failure    Should Not Match Regexp    ${response.text}    \\d+\\.\\d+\\.\\d+
    ...    msg=The health route shows a version number: ${response.text}
    FOR    ${header}    IN    X-Powered-By    Server
        Run Keyword And Continue On Failure    Dictionary Should Not Contain Key    ${response.headers}    ${header}
        ...    msg=The health route sends the ${header} header: ${response.headers}
    END

All assets load under the deployment sub-path
    [Documentation]    TC13-007. Expected result: every script, stylesheet, image and
    ...    the favicon of the build is served from under the deployment sub-path
    ...    and loads without errors (no 404, and no HTML page served in place of
    ...    a script or stylesheet). In the browser, the landing page loads every
    ...    resource from its own server without errors.
    [Tags]    api    browser
    ${files}=    Crawl Frontend Build    ${APP_URL}
    ${problems}=    Evaluate
    ...    [f['url'] + ' (' + str(f['status']) + ', from ' + f['found_in'] + ')' for f in $files if f['status'] is not None and (f['status'] != 200 or not f['url'].startswith($APP_URL) or (f['url'].endswith(('.js', '.css')) and f['text'].lstrip().lower().startswith('<!doctype')))]
    Run Keyword And Continue On Failure    Should Be Empty    ${problems}    msg=Assets that fail or are outside the sub-path: ${problems}
    ${main}=    Get Context Ids    ACTIVE    ACTIVE
    Open New Session
    TRY
        Wait For Elements State    .landing-image    visible    timeout=15s
        Wait For Load State    networkidle    timeout=15s
        ${failed}=    Evaluate JavaScript    ${None}
        ...    (appUrl) => performance.getEntriesByType('resource').concat(performance.getEntriesByType('navigation')).filter((e) => e.name.startsWith(location.origin) && (!e.name.startsWith(appUrl) || (e.responseStatus || 200) >= 400)).map((e) => e.name + ' (' + e.responseStatus + ')')
        ...    arg=${APP_URL}
        Should Be Empty    ${failed}    msg=Resources that failed or were outside the sub-path in the browser: ${failed}
    FINALLY
        Close Context
        Switch Context    ${main}[0]
    END


*** Keywords ***
Sign In For Security Tests
    [Documentation]    Signs the standard test account in, for the signed-in request
    ...    of TC13-001.
    Open Test Browser
    Open New Session
    Sign In

Clean Up Suite
    [Documentation]    Closes the browser.
    Close Browser

Headers Should Contain
    [Documentation]    Checks that the response has every expected header and that
    ...    each header's value contains the expected part.
    [Arguments]    ${response}    ${expected}    ${where}
    FOR    ${name}    ${part}    IN    &{expected}
        ${value}=    Evaluate    $response.headers.get($name)
        Run Keyword And Continue On Failure    Should Not Be Equal    ${value}    ${None}
        ...    msg=${where}: the ${name} header is missing
        IF    $value is not None
            Run Keyword And Continue On Failure    Should Contain    ${value}    ${part}
            ...    msg=${where}: ${name} is "${value}", expected it to contain "${part}"
        END
    END