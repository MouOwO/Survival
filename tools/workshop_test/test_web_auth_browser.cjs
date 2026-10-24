"use strict";

// Real Chrome behavior contract for the authorization-page Referrer-Policy.
// The Python HTTP tests separately bind the production route to this policy.
// All data here are synthetic; both servers and DevTools stay on loopback.
const assert = require("node:assert/strict");
const http = require("node:http");
const path = require("node:path");
const {browser, sleep} = require("../archive_official_variants_20261019/browser.cjs");

const KIND = "WS4-NATIVE-FORM-BROWSER-REGRESSION";
let stage = "initialize";

function reply(response, status, body, policy = "no-referrer") {
    response.writeHead(status, {
        "Content-Type": "text/html; charset=utf-8", "Content-Length": Buffer.byteLength(body),
        "Cache-Control": "no-store", "Referrer-Policy": policy, "Connection": "close",
        "Content-Security-Policy": "default-src 'none'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"
    });
    response.end(body);
}

function listen(server) {
    return new Promise((resolve, reject) => {
        server.once("error", reject);
        server.listen(0, "127.0.0.1", () => resolve("http://127.0.0.1:" + server.address().port));
    });
}

async function until(check, code) {
    for (let attempt = 0; attempt < 200; attempt++) {
        if (await check()) return;
        await sleep(50);
    }
    throw Error(code);
}

async function run() {
    const captures = new Map();
    let otherOrigin = "", active;
    const primary = http.createServer((request, response) => {
        const url = new URL(request.url, "http://127.0.0.1");
        const policy = url.pathname === "/form/no-referrer" ? "no-referrer"
            : url.pathname === "/form/same-origin" ? "same-origin" : null;
        if (request.method === "GET" && policy) {
            reply(response, 200, '<!doctype html><meta charset="utf-8"><title>Synthetic authorization</title>' +
                '<form id="native-auth" method="post" action="/capture/' + policy + '">' +
                '<input type="hidden" name="code" value="SYNTHETIC-CODE">' +
                '<input type="hidden" name="csrf" value="synthetic-csrf">' +
                '<button type="submit">Approve synthetic test</button></form>', policy);
            return;
        }
        if (request.method === "POST" && /^\/capture\/(no-referrer|same-origin)$/.test(url.pathname)) {
            let body = "";
            request.on("data", chunk => {
                body += chunk.toString("utf8");
                if (body.length > 2048) request.destroy();
            });
            request.on("end", () => {
                captures.set(url.pathname.slice("/capture/".length), {
                    method: request.method, origin: request.headers.origin, referer: request.headers.referer,
                    mode: request.headers["sec-fetch-mode"], destination: request.headers["sec-fetch-dest"],
                    contentType: request.headers["content-type"], body
                });
                reply(response, 200, "<!doctype html><title>Captured synthetic native form</title>");
            });
            return;
        }
        if (request.method === "GET" && url.pathname === "/outbound") {
            reply(response, 200, '<!doctype html><title>Synthetic outbound link</title>' +
                '<a id="to-other" href="' + otherOrigin + '/cross-capture">Other loopback origin</a>', "same-origin");
            return;
        }
        reply(response, 404, "<!doctype html><title>Unknown synthetic fixture</title>");
    });
    const secondary = http.createServer((request, response) => {
        if (request.method === "GET" && request.url === "/cross-capture") {
            captures.set("cross-origin", {method: request.method, referer: request.headers.referer,
                origin: request.headers.origin, mode: request.headers["sec-fetch-mode"]});
            reply(response, 200, "<!doctype html><title>Captured synthetic cross-origin navigation</title>");
        } else reply(response, 404, "<!doctype html><title>Unknown synthetic fixture</title>");
    });
    try {
        stage = "listen_loopback";
        const origin = await listen(primary);
        otherOrigin = await listen(secondary);
        assert.notEqual(origin, otherOrigin);
        stage = "launch_isolated_chrome";
        active = await browser({output: path.resolve(__dirname, "../../output/workshop_web_auth_browser"),
            executable: "C:/Program Files/Google/Chrome/Application/chrome.exe"});
        async function go(url) {
            const result = await active.call("Page.navigate", {url});
            assert(!result.errorText, "loopback_navigation_failed");
            await until(async () => {
                try { return await active.run("location.href === " + JSON.stringify(url) + " && document.readyState === 'complete'"); }
                catch (_) { return false; }
            }, "loopback_document_timeout");
        }
        for (const policy of ["no-referrer", "same-origin"]) {
            stage = "native_form_" + policy.replaceAll("-", "_");
            const source = origin + "/form/" + policy + "?code=SYNTHETIC-CODE";
            await go(source);
            // This is a native form navigation, with no fetch/XHR or injected
            // Origin/Referer headers. A timer lets the CDP evaluation return.
            await active.run("setTimeout(function(){document.getElementById('native-auth').requestSubmit();}, 0); true");
            await until(() => captures.has(policy), "native_form_capture_timeout");
            const captured = captures.get(policy);
            assert.equal(captured.method, "POST");
            assert.equal(captured.mode, "navigate");
            assert.equal(captured.destination, "document");
            assert(captured.contentType.startsWith("application/x-www-form-urlencoded"));
            assert.deepEqual(Object.fromEntries(new URLSearchParams(captured.body)),
                {code: "SYNTHETIC-CODE", csrf: "synthetic-csrf"});
            if (policy === "no-referrer") {
                assert.equal(captured.origin, "null", "no_referrer_native_post_must_have_null_origin");
                assert.equal(captured.referer, undefined);
            } else {
                assert.equal(captured.origin, origin, "same_origin_native_post_must_keep_its_origin");
                assert.equal(captured.referer, source);
            }
        }
        stage = "cross_origin_get";
        await go(origin + "/outbound?code=SYNTHETIC-CODE");
        await active.run("setTimeout(function(){document.getElementById('to-other').click();}, 0); true");
        await until(() => captures.has("cross-origin"), "cross_origin_capture_timeout");
        const cross = captures.get("cross-origin");
        assert.equal(cross.method, "GET");
        assert.equal(cross.mode, "navigate");
        assert.equal(cross.referer, undefined, "same_origin_policy_must_hide_the_code_from_other_origins");
        assert.equal(cross.origin, undefined);
        return {ok: true, kind: KIND, native_form_no_referrer_origin: "null",
            native_form_same_origin: "same_origin", cross_origin_get_referer: "absent",
            synthetic_data_only: true, steam_login_attempted: false, existing_browser_profile_used: false};
    } finally {
        if (active) await active.close();
        for (const server of [primary, secondary]) {
            server.closeAllConnections();
            if (server.listening) await new Promise(resolve => server.close(resolve));
        }
    }
}

module.exports = {run};
if (require.main === module) run().then(result => console.log(JSON.stringify(result))).catch(() => {
    console.log(JSON.stringify({ok: false, kind: KIND, error: "browser_regression_failed", stage}));
    process.exitCode = 1;
});
