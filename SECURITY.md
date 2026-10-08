# Security reporting

LiveTalk 2.8 is a preparation build. No App Store release, production purchase,
revenue advertising or approved commercial ChatGPT connection is currently enabled.
Private evaluation builds are not evidence that a production release is ready.

Report a suspected vulnerability through this repository's **Security → Report
a vulnerability** private reporting form, or privately to **doude424@gmail.com**
(ぞこーばスタジオ).
Include the app version, iOS version, a description of the effect and the minimum
steps needed to reproduce it. Redact personal information from any screenshots.
Do not send passwords, authentication codes, tokens, payment details, private
conversations or identity documents. Do not post those details in a public issue.

The preparation process checks source syntax, selected security invariants,
dependencies, native purchases, voice assets and shipped privacy declarations.
These checks are not an independent penetration test or a security guarantee.
Production network tests and independent review remain outstanding. The incident
response plan is in `docs/support-and-incidents.md`; operational response times
are still being confirmed before sale and no response deadline is promised here.

Third-party vulnerabilities must also be evaluated against the actual shipped
library version, configuration and provider guidance. A successful build or an
empty list of alerts is not proof that every binary dependency has been scanned.

Repository dependency, vulnerability and malware alerts are enabled. CodeQL
setup was requested for GitHub Actions, JavaScript/TypeScript and Python on
2026-10-09; its results must be checked separately. This setup does not cover
Swift or C/C++, binary-only SDKs, runtime traffic or the release-device checks.
