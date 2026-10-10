# Install the experimental IINA app on your iPad

You can build this app on a Mac and install it on your own iPad with Xcode, Apple's development app. **You do not need to write code or use Terminal.** The Xcode project is already included, so you do not need Homebrew or XcodeGen either.

This is the fork's experimental iPadOS app, not an official IINA release. There is currently no App Store listing, TestFlight invitation, or ready-made IPA download for this contribution. Opening the source ZIP on an iPad does not install it.

## Before you start

| You need | Details |
| --- | --- |
| A Mac | It must run a macOS version supported by your chosen Xcode. This route requires a Mac; Windows and an iPad alone cannot run Xcode. |
| Xcode 26 or newer | The project uses Icon Composer assets. Xcode 27 is used for the current checks. Choose a version that supports your iPad's installed iPadOS; see [Apple's Xcode compatibility table](https://developer.apple.com/support/xcode/). |
| An iPad with iPadOS 17 or newer | This is the project's minimum version, not a promise that every device/format has been tested. |
| An Apple Account | A free account can sign a personal test build. A paid Apple Developer Program membership is optional for this installation route. |
| A data-capable USB cable and internet access | Connect the iPad to the Mac. Xcode also downloads the playback dependencies and contacts Apple for signing. Allow space for Xcode and its downloads. |

**Free signing expires after seven days.** You can renew it by running the same project on the iPad again. Apple's Personal Team also limits installed apps and registered devices; see [Apple's account overview](https://developer.apple.com/help/account/basics/about-your-developer-account/). Read [Reinstall and update](#reinstall-and-update) before depending on the app for regular use.

## 1. Install Xcode and add your account

1. On the Mac, open the **App Store**, search for **Xcode** from Apple, and install it. Apple also provides downloads through its [Xcode website](https://developer.apple.com/xcode/).
2. Open Xcode once and finish its setup. Install the **iOS platform support** if prompted; iPadOS uses that platform. An iPad simulator is optional when installing on a real iPad.
3. In Xcode's menu bar, open **Xcode → Settings → Apple Accounts**. Some versions label the pane **Accounts**. Add your own Apple Account and complete Apple's sign-in prompts.

Your account and signing settings belong to your local copy. You do not need the fork owner's account or certificates. Apple's [account overview](https://developer.apple.com/help/account/basics/about-your-developer-account/) explains how Xcode creates a Personal Team for free accounts.

## 2. Download this branch and open the iPad project

1. On the Mac, open the fork's **[ipados branch](https://github.com/SleepAviator/iina/tree/ipados)**. The branch selector must say **ipados**, not **develop**.
2. Click the green **Code** button, then **Download ZIP**. You can also use this [direct branch ZIP link](https://github.com/SleepAviator/iina/archive/refs/heads/ipados.zip).
3. In Finder, double-click the ZIP to extract it. Keep the extracted folder in a local folder, for example a `Developer` folder inside your home folder. A local copy avoids cloud-sync delays while Xcode reads the project.
4. Open the extracted folder, open **iPadOS**, then double-click **IINAPad.xcodeproj**. Keep the whole repository folder together; the project uses the neighboring source files.
5. Wait for Xcode to finish resolving packages and downloading **MPVKit 1.0.0**. The download can take a while on the first build. Keep the pinned package version.

The repository also contains the macOS app's project. **Open the project inside `iPadOS`, not the root macOS project.** `IINAPad` is the project/scheme name; the installed app is named **IINA**.

## 3. Connect and prepare the iPad

1. Connect the iPad to the Mac with a data-capable cable. Unlock the iPad. Accept the computer-trust prompts on the iPad and in Finder if shown.
2. In Xcode's toolbar, choose **IINAPad** as the scheme and your **physical iPad** as the destination. An entry named “iPad … Simulator” is a virtual device on the Mac; “Any iOS Device” is not your connected iPad.
3. If the iPad is missing, open the destination menu and choose **Manage Devices** / **Device Hub**. Older Xcode versions use **Window → Devices and Simulators**. Wait for pairing and device preparation.
4. On the iPad, open **Settings → Privacy & Security → Developer Mode** and turn it on. Restart when prompted, then unlock the iPad and confirm enabling Developer Mode. The setting may only appear after pairing with Xcode.
5. Keep the iPad unlocked while Xcode installs and starts the app.

Apple documents [running on a physical device](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) and [enabling Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

## 4. Set up signing for your own iPad

Signing is Apple's way of allowing this development build to run on your device. You only need to change a few project settings:

1. In Xcode's left sidebar, click the blue **IINAPad** project icon. If the file sidebar is hidden, **⌘1** opens it.
2. In the project editor, select **IINAPad under TARGETS**, then open **Signing & Capabilities**. Choose the application target, not `IINAPadTests` or `IINAPadUITests`.
3. Enable **Automatically manage signing** and select your own **Team**. A free account appears as **Your Name (Personal Team)**.
4. Set a unique **Bundle Identifier**, such as `com.yourname.iinapad`, replacing `yourname` with your own unique identifier. Keep that same identifier for later updates.
5. If your Xcode version presents **Set Up Signing** instead, use it to select your team and enter the unique bundle identifier. Let Xcode register the device and create the development profile; click **Register Device** if it asks.

Do not change the app's source code, playback package, or entitlements to get through signing. The project does not supply someone else's developer team or signing material. Apple's [capability setup guide](https://developer.apple.com/documentation/xcode/adding-capabilities-to-your-app) and [device-running guide](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) describe these controls.

## 5. Install and open IINA

1. Confirm that the toolbar still shows **IINAPad → your physical iPad**.
2. Click the triangular **Run** button, or press **⌘R**. Xcode builds the app, installs it, and opens it on the iPad. The first build includes the playback libraries and takes longer than later builds.
3. If installation or launch fails, read the error in Xcode and use the table below. “Build Succeeded” alone does not confirm that installation and launch succeeded.
4. Once IINA opens, you can stop the debugging session with Xcode's square **Stop** button and reopen **IINA** from the iPad's Home Screen. The installed app can run without the Mac until its signing profile expires.

## 6. Play your first file

1. Copy a short video you own to the iPad's **Files** app, or choose a file already available there. A local MP4 is a useful first check before trying a network share or a large file.
2. In IINA, tap **Open File…** on the welcome screen or the folder button, then select that file. The synthetic color bars in our [screenshots](README.md#screenshots) are test media; they are not a loading screen.
3. Tap the video once to show or hide the controls. Use the speed button for **0.5×, 2×, 4×, or 8×**. With the default gesture settings, holding the video temporarily plays at **2×**, and a left/right swipe seeks **10 seconds** backward/forward.
4. Open the sliders/settings button for **Quick Settings**. Video contains track information and framing controls; Layout configures touch gestures and docked controls. Use the playlist button to manage files.

Playing local files does not require an OpenSubtitles account or API key. Those are only needed if you choose to use online subtitle search.

## Reinstall and update

With a **free Personal Team**, reconnect the iPad, open the same project, select the same team/bundle identifier and iPad, and press **⌘R** before or after the seven-day profile expires. You do not need to delete the app first. Keeping the same identity allows an update of the existing installation; deleting the app can remove its local settings and saved playlists. [Apple explains the seven-day limit here.](https://developer.apple.com/help/account/basics/about-your-developer-account/)

To try a newer version, download the `ipados` branch again, extract it into a separate folder, and repeat the opening/signing/run steps with **the same team and bundle identifier**. ZIP downloads do not automatically update. Keep the old project until the new one installs successfully. Paid developer signing has its own certificate/profile expiry; check Xcode if a build stops launching.

## If something goes wrong

| What you see | What to do |
| --- | --- |
| Only Mac destinations, or a macOS app opens | Close that project and open `iPadOS/IINAPad.xcodeproj`. Select the `IINAPad` scheme. |
| The iPad is absent, unavailable, or “locked” | Unlock it, use a data-capable cable, finish trust/pairing, and check Manage Devices / Device Hub. Update Xcode if it does not support the iPad's OS. |
| Developer Mode is missing or disabled | Pair the iPad with Xcode first, then enable it in Privacy & Security, restart, and confirm the prompt after restart. |
| “Signing requires a development team” | Select the `IINAPad` application target and your team in Signing & Capabilities. |
| Bundle identifier unavailable, or no matching profile | Choose a unique identifier, enable automatic signing, select your team and physical iPad, and let Xcode complete registration. |
| “Untrusted Developer” or a certificate-trust error | Follow the iPad/Xcode prompt. If asked, use **Settings → General → VPN & Device Management → Developer App** to trust your own account's development certificate, then retry. |
| Package download fails | Check the Mac's internet connection and retry resolving packages in Xcode. Keep MPVKit at `1.0.0`; use the first download/build error to diagnose the failure. |
| A free account hits an installed-app limit | Apple limits a Personal Team to **three apps per device**. Remove an unneeded personal test app if appropriate, taking care with its data, then retry. |
| IINA stops opening after about a week | Reinstall with the same team/bundle identifier using ⌘R. This renews free signing; it is not a playback problem. |
| A video fails after the app has opened | Try a short local MP4 and check Quick Settings → Video for the playback engine/diagnostics. Installation and format/network playback are separate checks. |

For help, report the **first relevant error**, Xcode version, iPad model, and iPadOS version when asking the fork maintainer for help. Remove account emails, device identifiers, credentials, and private file/share paths from any screenshots or logs you post.

For codec, renderer, and testing limitations, return to the [iPadOS README](README.md#tests-and-current-limits). This guide installs a personal development build; it does not certify an App Store release.
