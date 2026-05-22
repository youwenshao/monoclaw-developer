# MONOCLAW THIRD-PARTY OPEN SOURCE LICENSES AND ATTRIBUTIONS

This document lists the open-source software, libraries, tools, models, and third-party components shipped with or used by the MonoClaw product, along with their respective licenses and attribution requirements.

**This file is not the license for MonoClaw software itself.** MonoClaw is proprietary software developed by Sentimento Technologies Limited. Your rights to use MonoClaw are governed only by Sentimento’s legal terms (linked below), not by any open-source license in this document.

---

## 1. MonoClaw Product

**Developer:** Sentimento Technologies Limited

**Product license:** MonoClaw is proprietary software. It is not open-source and is not licensed under the MIT License or any other open-source license. Use, reproduction, and distribution of MonoClaw are governed by Sentimento’s legal terms:

* [Privacy Policy](https://www.monoclaw.app/privacy)
* [Terms of Service](https://www.monoclaw.app/terms)
* [Cookie Policy](https://www.monoclaw.app/cookies)
* [Acceptable Use Policy](https://www.monoclaw.app/acceptable-use-policy)

Nothing in this file grants you any rights to MonoClaw beyond those documents.

### Incorporated Open-Source Components

MonoClaw incorporates certain third-party open-source components. Those components remain licensed under their respective open-source terms; the notices below apply to those components only, not to MonoClaw as a whole.

**Hermes agent framework (Nous Research)** — Portions of the MonoClaw agent runtime are derived from the Hermes agent framework.

* **Upstream Project:** https://github.com/NousResearch/hermes-agent.git
* **Import Revision:** `7338e5d9c20c85256e5a45ad31edf8b7276e9c5ee1995` (squash-imported on 2026-05-08)
* **License:** MIT License
* **Copyright:** Copyright (c) 2025 Nous Research

**MonoClaw Achievements plugin**

* **License:** MIT License
* **Copyright:** Copyright (c) 2026 Hermes Achievements contributors

---

## 2. Models and Proprietary Integrations

MonoClaw may include or use the following third-party machine learning models and local inference software on your Mac:

### Google Gemma 4 Model
MonoClaw may ship with the Google Gemma 4 Effective 4B (E4B) model (`gemma-4-E4B-it-Q4_K_M.gguf` and `mmproj-gemma-4-E4B-it-f16.gguf`).
* **License:** Apache License, Version 2.0 (Google open-source release, April 2026)
* **Copyright:** Copyright (c) 2026 Google LLC
* **Project Page:** https://ai.google.dev/gemma

### LM Studio Desktop Application
MonoClaw may use **LM Studio** (`LM Studio.app`) for local model execution.
* **License:** Proprietary (Free for Personal and Commercial Use)
* **Copyright:** Copyright (c) 2025 Element Labs Inc. (ai.elementlabs.lmstudio)
* **Terms of Service:** Subject to the LM Studio App Terms of Service (updated July 1, 2025). Free for internal business and personal use. This is not open-source software.

---

## 3. Bundled Runtimes

MonoClaw includes Python and Node.js runtimes used by the product:

### CPython Runtime (Python 3.13)
The core runtime virtual environment is constructed from a prebuilt Python distribution.
* **Source:** Python Standalone Builds (astral-sh / python-build-standalone)
* **CPython License:** Python Software Foundation License Version 2 (PSF)
* **Build Mechanism License:** Mozilla Public License Version 2.0 (MPL-2.0)
* **Copyright:** Copyright (c) Python Software Foundation; Copyright (c) Gregory Szorc

### Node.js (v26.0.0)
Node.js v26 is included to drive secretary tools and other Node-based subsystems.
* **License:** MIT License
* **Copyright:** Copyright Node.js contributors. All rights reserved. Portions Copyright Joyent, Inc. and other Node contributors.

---

## 4. Secretary Tools

The following secretary tools may be included with MonoClaw. Each is licensed under the MIT License:

* **wacrawl** (v0.2.0)
  * **License:** MIT License
  * **Repository:** https://github.com/steipete/wacrawl
  * **Copyright:** Copyright (c) Peter Steinberger
* **slacrawl** (v0.5.0)
  * **License:** MIT License
  * **Repository:** https://github.com/vincentkoc/slacrawl
  * **Copyright:** Copyright (c) Vincent Koc
* **summarize** (v0.14.1)
  * **License:** MIT License
  * **Repository:** https://github.com/steipete/summarize
  * **Copyright:** Copyright (c) Peter Steinberger
* **macos-automator-mcp** (v0.4.1)
  * **License:** MIT License
  * **Repository:** https://github.com/steipete/macos-automator-mcp
  * **Copyright:** Copyright (c) Peter Steinberger
* **conduit-mcp** (v1.0.0)
  * **License:** MIT License
  * **Repository:** https://github.com/steipete/conduit-mcp
  * **Copyright:** Copyright (c) Peter Steinberger
* **ghcrawl** (v0.8.0)
  * **License:** MIT License
  * **Repository:** https://github.com/steipete/ghcrawl
  * **Copyright:** Copyright (c) Peter Steinberger

---

## 5. Skill Companion Tools

The following optional skill companion tools may be included with MonoClaw:

* **remindctl** (v0.2.0)
  * **License:** MIT License
  * **Repository:** https://github.com/openclaw/remindctl
  * **Copyright:** Copyright (c) OpenClaw contributors
* **imsg** (v0.5.0)
  * **License:** MIT License
  * **Repository:** https://github.com/steipete/imsg
  * **Copyright:** Copyright (c) Peter Steinberger
* **himalaya** (v1.2.0)
  * **License:** MIT License
  * **Repository:** https://github.com/pimalaya/himalaya
  * **Copyright:** Copyright (c) Pimalaya contributors
* **memo** (v0.5.3)
  * **License:** Apache License, Version 2.0
  * **Repository:** https://github.com/antoniorodr/memo
  * **Copyright:** Copyright (c) Antonio Rodriguez

---

## 6. System Dependencies

During MonoClaw setup, your Mac may also install or use the following third-party software (for example via Homebrew):

* **Homebrew**
  * **License:** BSD 2-Clause License
  * **Copyright:** Copyright (c) Homebrew contributors
* **uv** (Astral Python environment manager)
  * **License:** MIT License / Apache License 2.0 (Dual-licensed)
  * **Copyright:** Copyright (c) Astral Software Inc.
* **ripgrep** (rg)
  * **License:** MIT License / Unlicense (Dual-licensed)
  * **Copyright:** Copyright (c) Andrew Gallant
* **libopus** (Opus audio codec)
  * **License:** BSD 3-Clause License
  * **Copyright:** Copyright (c) Xiph.Org Foundation, Skype Limited, and contributors
* **ffmpeg**
  * **License:** GNU Lesser General Public License, Version 2.1 or later (LGPL-2.1+)
  * **Copyright:** Copyright (c) FFmpeg developers
* **agent-browser** (v0.26.0)
  * **License:** Apache License, Version 2.0
  * **Repository:** https://github.com/vercel-labs/agent-browser
  * **Copyright:** Copyright (c) Vercel Labs

---

## 7. Python Runtime Dependencies (PIP Packages)

MonoClaw ships with bundled Python libraries used by the runtime. These packages are grouped by their license types below:

### Apache License 2.0
* **openai** (OpenAI client)
* **requests** (HTTP library)
* **tenacity** (Retry library)
* **firecrawl-py** (Firecrawl SDK)
* **fire** (CLI generator)
* **cryptography** (Cryptographic primitives)
* **aiohttp** (Asynchronous HTTP)
* **packaging** (Package utilities)
* **fal-client** (Fal API integration)
* **PyNaCl** (Networking and Cryptography)
* **pydantic**, **pydantic-core**, **pydantic-settings** (Data validation)
* **starlette**, **fastapi**, **sse-starlette** (Web framework)
* **anyio** (Asynchronous I/O)
* **websockets** (WebSocket protocol)
* **idna** (Internationalized Domain Names)
* **multidict** (Multidict container)
* **propcache** (Property caching)
* **brotli** (Brotli compression)
* **charset-normalizer** (Charset detection)
* **click** (Command line interfaces)
* **distro** (OS platform distribution)
* **urllib3** (HTTP client)
* **yarl** (URL parsing)
* **referencing**, **rpds-py** (JSON Schema support)
* **python-multipart** (Multipart form parsing)
* **annotated-types** (Type annotations)
* **watchfiles** (File watching)
* **sniffio** (Async library sniffer)

### MIT License
* **anthropic** (Anthropic client)
* **rich** (Terminal text formatting)
* **ddgs** (DuckDuckGo Search)
* **croniter** (Cron expression scheduler)
* **PyJWT** (JSON Web Tokens)
* **cffi** (Foreign Function Interface for Python)
* **python-dotenv** (Environment file configuration)
* **httpx**, **socksio**, **python-socks** (HTTP client and proxy support)
* **edge-tts** (Microsoft Edge Text-to-Speech)
* **exa-py** (Exa search client)
* **uvloop** (Fast asyncio event loop)
* **tqdm** (Progress bars)
* **qrcode** (QR code generator)
* **six** (Python 2 and 3 compatibility utilities)
* **typing-extensions** (Backported type hints)
* **attrs** (Classes without boilerplate)
* **wcwidth** (Unicode terminal width calculation)
* **pyyaml** (YAML parser and emitter)
* **frozenlist** (Frozen list implementation)
* **aiosignal** (Signal handling for asyncio)
* **nest-asyncio** (Nested event loops support)

### BSD 3-Clause License
* **jinja2** (Template engine)
* **pycparser** (C parser in Python)
* **pygments** (Syntax highlighter)

### ISC License
* **ptyprocess** (PTY process control)
  * **Copyright:** Copyright (c) Pexpect development team

### Mozilla Public License 2.0 (MPL-2.0)
* **certifi** (Certificate authority bundle)

### GNU Lesser General Public License (LGPL)
* **python-telegram-bot** (v22.7) — Licensed under LGPL v3.0.
* **audioop_lts** — CPython stdlib audioop backport for Python 3.13, licensed under LGPL.
* **davey** — Backports/compatibility helpers, licensed under LGPL.

---

## 8. Node.js & Terminal UI Subsystems

MonoClaw provides an interactive terminal user interface (TUI) and a messaging platform gateway. Their dependencies include:

### React Terminal UI (ui-tui) Dependencies
* **ink** (React terminal renderer)
  * **License:** MIT License
  * **Copyright:** Copyright (c) Vadim Demedes and Sindre Sorhus
* **react**, **react-dom**
  * **License:** MIT License
  * **Copyright:** Copyright (c) Meta Platforms, Inc. and affiliates
* **nanostores**, **@nanostores/react**
  * **License:** MIT License
  * **Copyright:** Copyright (c) Andrey Sitnik
* **ink-text-input**
  * **License:** MIT License
  * **Copyright:** Copyright (c) Vadim Demedes
* **unicode-animations**
  * **License:** MIT License
  * **Copyright:** Copyright (c) Vadim Demedes

### WhatsApp Bridge Dependencies
* **@whiskeysockets/baileys** (WhatsApp API library)
  * **License:** MIT License
  * **Copyright:** Copyright (c) 2025 Rajeh Taher / WhiskeySockets
* **express** (Web framework)
  * **License:** MIT License
  * **Copyright:** Copyright (c) TJ Holowaychuk and contributors
* **pino** (Fast logger)
  * **License:** MIT License
  * **Copyright:** Copyright (c) Matteo Collina and contributors
* **qrcode-terminal**
  * **License:** MIT License

---

## Appendix: Full Open-Source License Texts (Third-Party Components)

The license texts below apply to third-party open-source components listed in this document, not to MonoClaw proprietary software.

### 1. The MIT License (MIT)

```
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

### 2. Apache License, Version 2.0 (Apache-2.0)

```
Apache License
Version 2.0, January 2004
http://www.apache.org/licenses/

TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

1. Definitions.

   "License" shall mean the terms and conditions for use, reproduction,
   and distribution as defined by Sections 1 through 9 of this document.

   "Licensor" shall mean the copyright owner or entity authorized by
   the copyright owner that is granting the License.

   "Legal Entity" shall mean the union of the acting entity and all
   other entities that control, are controlled by, or are under common
   control with that entity. For the purposes of this definition,
   "control" means (i) the power, direct or indirect, to cause the
   direction or management of such entity, whether by contract or
   otherwise, or (ii) ownership of fifty percent (50%) or more of the
   outstanding shares, or (iii) beneficial ownership of such entity.

   "You" (or "Your") shall mean an individual or Legal Entity
   exercising permissions granted by this License.

   "Source" form shall mean the preferred form for making modifications,
   including but not limited to software source code, documentation
   source, and configuration files.

   "Object" form shall mean any form resulting from mechanical
   transformation or translation of a Source form, including but
   not limited to compiled object code, generated documentation,
   and conversions to other media types.

   "Work" shall mean the work of authorship, whether in Source or
   Object form, made available under the License, as indicated by a
   copyright notice that is included in or attached to the work
   (an example is provided in the Appendix below).

   "Derivative Works" shall mean any work, whether in Source or Object
   form, that is based on (or derived from) the Work and for which the
   editorial revisions, annotations, elaborations, or other modifications
   represent, as a whole, an original work of authorship. For the purposes
   of this License, Derivative Works shall not include works that remain
   separable from, or merely link (or bind by name) to the interfaces of,
   the Work and Derivative Works thereof.

   "Contribution" shall mean any work of authorship, including
   the original version of the Work and any modifications or additions
   to that Work or Derivative Works thereof, that is intentionally
   submitted to Licensor for inclusion in the Work by the copyright owner
   or by an individual or Legal Entity authorized to submit on behalf of
   the copyright owner. For the purposes of this definition, "submitted"
   means any form of electronic, verbal, or written communication sent
   to the Licensor or its representatives, including but not limited to
   communication on electronic mailing lists, source code control systems,
   and issue tracking systems that are managed by, or on behalf of, the
   Licensor for the purpose of discussing and improving the Work, but
   excluding communication that is conspicuously marked or otherwise
   designated in writing by the copyright owner as "Not a Contribution."

   "Contributor" shall mean Licensor and any individual or Legal Entity
   on behalf of whom a Contribution has been received by Licensor and
   subsequently incorporated within the Work.

2. Grant of Copyright License. Subject to the terms and conditions of
   this License, each Contributor hereby grants to You a perpetual,
   worldwide, non-exclusive, no-charge, royalty-free, irrevocable
   copyright license to reproduce, prepare Derivative Works of,
   publicly display, publicly perform, sublicense, and distribute the
   Work and such Derivative Works in Source or Object form.

3. Grant of Patent License. Subject to the terms and conditions of
   this License, each Contributor hereby grants to You a perpetual,
   worldwide, non-exclusive, no-charge, royalty-free, irrevocable
   (except as stated in this section) patent license to make, have made,
   use, offer to sell, sell, import, and otherwise transfer the Work,
   where such license applies only to those patent claims licensable
   by such Contributor that are necessarily infringed by their
   Contribution(s) alone or by combination of their Contribution(s)
   with the Work to which such Contribution(s) was submitted. If You
   institute patent litigation against any entity (including a
   cross-claim or counterclaim in a lawsuit) alleging that the Work
   or a Contribution incorporated within the Work constitutes direct
   or contributory patent infringement, then any patent licenses
   granted to You under this License for that Work shall terminate
   as of the date such litigation is filed.

4. Redistribution. You may reproduce and distribute copies of the
   Work or Derivative Works thereof in any medium, with or without
   modifications, and in Source or Object form, provided that You
   meet the following conditions:

   (a) You must give any other recipients of the Work or
       Derivative Works a copy of this License; and

   (b) You must cause any modified files to carry prominent notices
       stating that You changed the files; and

   (c) You must retain, in the Source form of any Derivative Works
       that You distribute, all copyright, patent, trademark, and
       attribution notices from the Source form of the Work,
       excluding those notices that do not pertain to any part of
       the Derivative Works; and

   (d) If the Work includes a "NOTICE" text file as part of its
       distribution, then any Derivative Works that You distribute must
       include a readable copy of the attribution notices contained
       within such NOTICE file, excluding those notices that do not
       pertain to any part of the Derivative Works, in at least one
       of the following places: within a NOTICE text file distributed
       as part of the Derivative Works; within the Source form or
       documentation, if distributed along with the Derivative Works; or,
       within a display generated by the Derivative Works, if and
       wherever such third-party notices normally appear. The contents
       of the NOTICE file are for informational purposes only and
       do not modify the License. You may add Your own attribution
       notices within Derivative Works that You distribute, alongside
       or as an addendum to the Work text from the Licensor, provided
       that such additional attribution notices cannot be construed
       as modifying the License.

   You may add Your own copyright statement to Your modifications and
   may provide additional or different license terms and conditions
   for use, reproduction, or distribution of Your modifications, or
   for any such Derivative Works as a whole, provided Your use,
   reproduction, and distribution of the Work otherwise complies with
   the conditions stated in this License.

5. Submission of Contributions. Unless You explicitly state otherwise,
   any Contribution intentionally submitted for inclusion in the Work
   by You to the Licensor shall be under the terms and conditions of
   this License, without any additional terms or conditions.
   Notwithstanding the above, nothing herein shall supersede or modify
   the terms of any separate license agreement you may have executed
   with Licensor regarding such Contributions.

6. Trademarks. This License does not grant permission to use the trade
   names, trademarks, service marks, or product names of the Licensor,
   except as required for reasonable and customary use in describing the
   origin of the Work and reproducing the content of the NOTICE file.

7. Disclaimer of Warranty. Unless required by applicable law or
   agreed to in writing, Licensor provides the Work (and each
   Contributor provides its Contributions) on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
   implied, including, without limitation, any warranties or conditions
   of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
   PARTICULAR PURPOSE. You are solely responsible for determining the
   appropriateness of using or redistributing the Work and assume any
   risks associated with Your exercise of permissions under this License.

8. Limitation of Liability. In no event and under no legal theory,
   whether in tort (including negligence), contract, or otherwise,
   unless required by applicable law (such as deliberate and grossly
   negligent acts) or agreed to in writing, shall any Contributor be
   liable to You for damages, including any direct, indirect, special,
   incidental, or consequential damages of any character arising as a
   result of this License or out of the use or inability to use the
   Work (including but not limited to damages for loss of goodwill,
   work stoppage, computer failure or malfunction, or any and all
   other commercial damages or losses), even if such Contributor
   has been advised of the possibility of such damages.

9. Accepting Warranty or Additional Liability. While redistributing
   the Work or Derivative Works thereof, You may choose to offer,
   and charge a fee for, acceptance of support, warranty, indemnity,
   or other liability obligations and/or rights consistent with this
   License. However, in accepting such obligations, You may act only
   on Your own behalf and on Your sole responsibility, not on behalf
   of any other Contributor, and only if You agree to indemnify,
   defend, and hold each Contributor harmless for any liability
   incurred by, or claims asserted against, such Contributor by reason
   of your accepting any such warranty or additional liability.
```

---

### 3. Python Software Foundation License Version 2 (PSF)

```
1. This LICENSE AGREEMENT is between the Python Software Foundation ("PSF"), and
   the Individual or Organization ("Licensee") accessing and otherwise using this
   software ("Python") in source or binary form and its associated documentation.

2. Subject to the terms and conditions of this License Agreement, PSF hereby
   grants Licensee a nonexclusive, royalty-free, world-wide license to reproduce,
   analyze, test, perform and/or display publicly, prepare derivative works,
   distribute, and otherwise use Python alone or in any derivative version,
   provided, however, that PSF's License Agreement and PSF's notice of copyright,
   i.e., "Copyright (c) 2001-2026 Python Software Foundation; All Rights Reserved"
   are retained in Python alone or in any derivative version prepared by Licensee.

3. In the event Licensee prepares a derivative work that is based on or
   incorporates Python or any part thereof, and wants to make the derivative
   work available to others as provided herein, then Licensee hereby agrees to
   include in any such work a brief summary of the changes made to Python.

4. PSF is making Python available to Licensee on an "AS IS" basis. PSF MAKES NO
   REPRESENTATIONS OR WARRANTIES, EXPRESS OR IMPLIED. BY WAY OF EXAMPLE, BUT NOT
   LIMITATION, PSF MAKES NO AND DISCLAIMS ANY REPRESENTATION OR WARRANTY OF
   MERCHANTABILITY OR FITNESS FOR ANY PARTICULAR PURPOSE OR THAT THE USE OF
   PYTHON WILL NOT INFRINGE ANY THIRD PARTY RIGHTS.

5. PSF SHALL NOT BE LIABLE TO LICENSEE OR ANY OTHER USERS OF PYTHON FOR ANY
   INCIDENTAL, SPECIAL, OR CONSEQUENTIAL DAMAGES OR LOSS AS A RESULT OF
   MODIFYING, DISTRIBUTING, OR OTHERWISE USING PYTHON, OR ANY DERIVATIVE
   THEREOF, EVEN IF ADVISED OF THE POSSIBILITY THEREOF.

6. This License Agreement will automatically terminate if Licensee fails to
   comply with any terms and conditions herein.

7. Nothing in this License Agreement shall be deemed to create any relationship
   of agency, partnership, or joint venture between PSF and Licensee. This
   License Agreement does not grant permission to use PSF trademarks or trade
   names in a trademark sense to endorse or promote products or services of
   Licensee, or any third party.

8. By copying, installing or otherwise using Python, Licensee agrees to be
   bound by the terms and conditions of this License Agreement.
```

---

### 4. Mozilla Public License Version 2.0 (MPL-2.0)

```
Mozilla Public License, version 2.0

1. Definitions
1.1. "Contributor" means each individual or legal entity that creates, contributes to the creation of, or owns Covered Software.
1.2. "Contributor Version" means the combination of the Contributions of others (if any) used by a Contributor and that particular Contributor's Contribution.
1.3. "Contribution" means Covered Software of a particular Contributor.
1.4. "Covered Software" means Source Code Form to which the initial Contributor has attached the notice in Exhibit A, the Executable Form of such Source Code Form, and Modifications of such Source Code Form, in each case including portions thereof.
1.5. "Incompatible With Secondary Licenses" means
     a. that the initial Contributor or other Contributor as allowed by Section 3.4 has not joined the Compatible License(s) to the Covered Software; or
     b. that the Covered Software was made available under the Mozilla Public License, version 1.1 or earlier, and is not incompatible with secondary licenses.
1.6. "Executable Form" means any form other than Source Code Form.
1.7. "Larger Work" means a work that combines Covered Software with other material, in a separate file or files, that is not Covered Software.
1.8. "License" means this document.
1.9. "Licensable" means having the right to grant, to the maximum extent possible, whether at the time of the initial grant or subsequently, any and all of the rights conveyed by this License.
1.10. "Modifications" means any of the following:
      a. any file in Source Code Form that results from an addition to, deletion from, or modification of the contents of Covered Software; or
      b. any new file in Source Code Form that contains any Covered Software.
1.11. "Patent Claims" of a Contributor means any patent claim(s), including without limitation method, process, and apparatus claims, in any patent Licensable by such Contributor that would be infringed, but for the grant of the License, by the making, using, selling, offering for sale, having made, import, or transfer of either its Contributions or its Contributor Version.
1.12. "Secondary License" means either the GNU General Public License, Version 2.0, the GNU Lesser General Public License, Version 2.1, the GNU Affero General Public License, Version 3.0, or any later versions of those licenses.
1.13. "Source Code Form" means the common form of computer software code in which modifications are made, including associated documentation, schema definitions, and inline comments.
1.14. "You" (or "Your") means an individual or a legal entity exercising rights under this License.

2. License Grants and Conditions
2.1. Grants
Each Contributor hereby grants You a world-wide, royalty-free, non-exclusive license:
     a. under intellectual property rights (other than patent or trademark) Licensable by such Contributor to use, reproduce, make available, modify, display, perform, distribute, and otherwise make available its Contributions, either on an unmodified basis, with Modifications, or as part of a Larger Work; and
     b. under Patent Claims to make, use, sell, offer for sale, have made, import, and otherwise transfer its Contributions or its Contributor Version.
2.2. Effective Date
The licenses granted in Section 2.1 with respect to any Contribution become effective for each Contribution on the date the Contributor first distributes such Contribution.
2.3. Limitations on Grant
The licenses granted in this Section 2 are the only rights granted under this License. No additional patents or other intellectual property rights are granted by implication, estoppel, or otherwise.
The licenses granted in Section 2.1.b do not apply to any Patent Claims which are infringed by:
     a. Your modification of the Covered Software; or
     b. the combination of Covered Software with other software or hardware.
No patent license is granted for claims that are infringed by the combination of Covered Software with other software or hardware.
No license is granted for CPython dependencies that are not Covered Software.

Covered Software distributed under this License remains subject to the terms of this License. You may distribute Covered Software in Executable Form, provided that You also make the Source Code Form available and inform recipients how they can obtain such Source Code Form.
```

---

### 5. GNU Lesser General Public License, Version 3.0 (LGPL-3.0)

```
MonoClaw incorporates the python-telegram-bot library, which is licensed under the
GNU Lesser General Public License Version 3.0 (LGPL-3.0).

In compliance with the LGPL:
1. You may obtain the complete machine-readable source code for the python-telegram-bot
   library from its official repository: https://github.com/python-telegram-bot/python-telegram-bot
2. You have the right to modify the library and relink the application to use your modified
   version. Since python-telegram-bot is a Python library, the code remains dynamically
   imported at runtime, satisfying the requirements of dynamic linking under Section 4 of the LGPL.
3. No changes were made by the MonoClaw team to the python-telegram-bot library code or its wheels.
```

---

### 6. The BSD 3-Clause License (BSD-3-Clause)

```
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```
