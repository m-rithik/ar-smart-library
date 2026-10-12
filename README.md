# AR Smart Library

A native iPhone AR application that uses ARKit, LiDAR scene depth, Vision text recognition, and a local book catalog to identify a book and display:

- an AR marker anchored to the measured shelf position;
- title, author, genre, rating, and summary;
- three explainable, content-based recommendations with similar, exploratory, and highly rated modes;
- a live **Find on shelf** flow for a selected recommendation;
- a saved AR room with admin-defined shelf rows, book positions, and recorded aisle routes;
- an illustrated catalog with grid/list browsing, genre filters, multi-term search, and title/author/rating sorting;
- an on-device reading shelf with Want to read, Reading, and Finished statuses;
- catalog search with directions to the assigned shelf and a cyan AR row outline;
- a two-book comparison of themes, genre, rating, and content overlap; and
- exact/possible placement states, with guidance to move closer when the match is weak.

The app performs all recognition and ranking on the phone. It has no server or third-party runtime dependency.

## Requirements

- iPhone 17 Pro or another ARKit-capable iPhone; LiDAR is used when available.
- A Mac with Xcode to build and sign the app. Running through Xcode's debugger also requires support for the connected phone.
- Check the phone's iOS version against [Apple's Xcode device support and macOS requirements](https://developer.apple.com/xcode/system-requirements).
- An Apple Account added to Xcode. A paid developer membership is not required for testing on your own phone.

## Install on iPhone 17 Pro

1. Check that the installed Xcode supports the phone's current iOS version. This project does not require you to update your Mac to continue developing and testing the catalog and non-hardware logic in Simulator. If Xcode cannot prepare the phone, see the USB installation option below; changing the app's deployment target does not fix device-support errors.
2. Open `ARSmartLibrary.xcodeproj` in Xcode.
3. Connect the iPhone by USB-C, unlock it, and tap **Trust** if prompted.
4. In Xcode, open **Settings > Accounts** and add your Apple Account.
5. Select the **ARSmartLibrary** project, choose the **ARSmartLibrary** target, and open **Signing & Capabilities**.
6. Select your Personal Team. Keep **Automatically manage signing** enabled. If Xcode reports a bundle-ID conflict, replace `com.rithikmeedinti.ARSmartLibrary` with a unique identifier.
7. Select the connected iPhone 17 Pro as the run destination and press **Run**.
8. If requested, enable **Settings > Privacy & Security > Developer Mode** on the iPhone, restart it, confirm Developer Mode, and press **Run** again.
9. Allow camera access when the app launches.

A free Personal Team profile expires after seven days; reconnect, renew the profile in Xcode, and rebuild and reinstall the app.

### USB installation when Xcode cannot prepare the phone

On October 12, 2026, installation succeeded on an iPhone 17 Pro running iOS 27.0 beta (24A435), using macOS 15.3.1 without updating macOS. Xcode 16.4 created the Personal Team provisioning profile for the connected phone. Xcode 16.2 then built and signed the Release app. Xcode's installer remained blocked by a missing developer disk image variant, but [ideviceinstaller](https://github.com/libimobiledevice/ideviceinstaller) installed the signed IPA over USB, and the phone reported `ProfileValidated = true`.

This route requires a valid Apple signing certificate and an unexpired provisioning profile that includes the phone. It does not provide Xcode debugging support. With a freshly signed IPA at `build/ARSmartLibrary.ipa` and the phone connected and trusted:

```sh
brew install ideviceinstaller
ideviceinstaller install build/ARSmartLibrary.ipa
ideviceinstaller list --bundle-identifier com.rithikmeedinti.ARSmartLibrary
```

The signed IPA is a local build artifact and is not committed to Git. Package only the `Payload` directory and exclude `._*` and `.DS_Store` metadata files. Open **AR Smart Library** on the phone after installation and allow camera access. Physical AR behavior still needs the acceptance checks below.

## Use

1. Hold the phone in portrait orientation.
2. Point the center reticle at a title on a cover or book spine.
3. Hold steady for two OCR observations while LiDAR maps the surface.
4. The app anchors a green exact marker or a larger orange possible-region marker and opens the information panel.
5. Change **Similar** to **Explore** or **Top rated** to change the recommendation objective.
6. Tap a recommendation's **Find on shelf** action. If an admin assigned a location, follow the saved route to the row; otherwise the app searches for the title in the live camera view.
7. Tap **Compare**, scan a different book, and review their shared themes and content overlap.
8. Tap **Scan another** or **Start over** to reset the local track.
9. Use the layers button to inspect the LiDAR reconstruction mesh.

The included catalog contains twelve demonstration titles in `ARSmartLibrary/Resources/BookCatalog.json`. Add your own titles using **Add book** in the app. Recognition matches the bundled catalog and your saved custom books.

## Browse and save your next read

Open **Library** from the scanner. Simulator and devices without AR open directly into the catalog. The browser includes original typographic cover artwork, a featured title, genre chips, grid/list layouts, and the number of books with assigned shelf locations. The artwork represents the catalog, not a particular published edition.

- Search by title, author, summary, or topic. Multiple words narrow the results, and accents are optional (for example, `bronte`).
- Use the sort button for **Title**, **Author**, or **Top rated**, and to show only books with shelf directions.
- Open a book for its summary, themes, recommendations, and shelf guidance.
- Use **Save to my list** to choose **Want to read**, **Reading**, or **Finished**. **My list** filters your saved books by status. Change the status or remove a book from the same menu.
- Reading statuses persist on this iPhone across launches. They are separate from the AR room map and do not alter recommendation ranking.
- Large accessibility text switches the collection to a vertical list.

The sliders button opens **Library setup**. Choose **Reader** there to return to browsing.

## Add your own books

1. Open **Library** or **Library setup** and tap **Add book** at the top left.
2. Enter the title as printed on the cover or spine, and the author. Optionally add a genre, description, comma-separated keywords, and your rating.
3. Tap **Save**. The book's details open, and it is immediately available in search, scanning, recommendations, reading lists, and the shelf assignment picker.

Custom books are stored locally and survive app restarts and app updates. Adding one does not require a mapped room or discard a room or shelf draft. Duplicate title/author pairs are rejected. Omitted ratings appear as **Not rated**; entered ratings are labeled **your rating**. The app does not fetch book information or cover photos online. Uninstalling the app removes its local books and library data.

## Set up the AR library as an admin

1. Tap the **books** button to open **Library**, then tap the **sliders** button to open **Library setup**.
2. Name the room and tap **Create AR space**. This starts a working map. An older saved space stays on disk until a new save succeeds.
3. Start at a recognizable entrance or aisle junction. Slowly scan walls, shelves, and the floor until the room is aligned.
4. Open **Manage shelves and book locations** and expand **Add a shelf row**. Enter its label (for example, A3), row (second from top), physical width/height, and optional directions.
5. Tap **Record route and place shelf**. At the entrance, tap **Record stop**. Walk the clear aisle route and record a stop at each turn. Keep consecutive route segments inside the walkable aisle. Undo removes the most recent stop.
6. Aim the reticle at the center of the destination shelf row and tap **Place shelf row here**. The cyan outline follows the detected vertical shelf surface. When only depth is available, face the shelf straight-on because its orientation is estimated from the camera. Move closer or scan the surface if placement is unavailable.
7. Open Library again. Under **Assign or edit a book location**, choose a catalog book, the row, and a position such as “third from left.” Repeat for the books on that row.
8. Repeat from the same entrance for other shelf rows. Scan the route and shelf surroundings from several angles, then tap **Save AR space** when available.

The app stores the ARKit world map, named shelf/aisle anchors, book assignments, and an entrance reference image together in one atomic local file. Save is blocked while placement is unfinished or tracking is unavailable. Removing a shelf also removes its book assignments; save to persist the removal. The last shelf can be removed and the resulting empty map saved.

Each shelf lists its assigned books and positions. Edit a book's assignment to move it or correct its slot; remove an individual assignment without deleting the shelf or other books. Switching away from an unfinished route asks before discarding it. A failed restore keeps the working map and draft intact.

## Find a book in the saved space

1. Open **Library** and search by title, author, genre, or topic. Search also covers summaries and keywords.
2. Filter by genre or assigned locations, then open a book to read its full details and related titles. Choose **Take me to this book** for an assigned book, or **Scan for this title** for an unassigned one. Catalog browsing works without camera access or AR hardware; spatial actions explain when they are unavailable.
3. After reopening the app, return to the reference entrance view and slowly look around. ARKit must align the camera with the saved map before any spatial directions appear. If alignment fails, **Retry room alignment** reloads the saved map; it never assumes alignment succeeded.
4. Follow the large white arrow over the live camera and the distance to the next stop. The arrow gently moves forward and smoothly turns with your phone, including when the direction crosses behind you; Reduce Motion disables these animations. It disappears when tracking is unavailable or you reach the shelf. The route visits the admin's stops in sequence, starting at the recorded entrance; the yellow marker shows the current stop.
5. At the destination, the **cyan outline** points out the shelf row. The card shows the shelf label, row, and book position.
6. Tap **Scan title to confirm** to check the actual book through OCR. A stored assignment alone does not verify that a book has not moved.

This version stores one space on one iPhone. Admin/Reader are local working modes, without account authentication or cross-device synchronization. Routes are manually recorded for a small mapped room; they do not calculate detours around new obstacles or provide a building-wide floor plan. Keep the walkway in view and stop if a route is blocked. Pause/background and temporary tracking loss hide directions while preserving the working coordinate frame. A fatal AR error offers a manual retry; restarting requires confirmation when unsaved work exists, restores the last valid saved space, and reports discarded coordinates.

The saved-map implementation follows [Apple's ARWorldMap save/restore workflow](https://developer.apple.com/documentation/arkit/saving-and-loading-world-data).

## On-device ML pipeline

The app is deliberately offline and transparent:

1. **Vision OCR** reads text inside the reticle. Catalog titles and authors are supplied as recognition hints.
2. **Book matching** combines distinctive title words, author evidence, OCR confidence, edit similarity for small OCR mistakes, runner-up separation, and two-frame temporal confirmation. Common words such as “the” and “of” cannot inflate a different title into a confirmed match.
3. **TF-IDF fitting** converts each local catalog record—title, author, genre, keywords, and summary—into a weighted text vector at runtime.
4. **Cosine similarity** ranks related books. Rating is a smaller prior, and unrelated high-rated books are rejected.
5. **Intent reranking** changes the objective: Similar emphasizes relevance, Explore rewards a thematic bridge into another genre and penalizes repetitive results, and Top rated gives rating more weight while retaining relevance.
6. **LiDAR/ARKit** measures and anchors the recognized title. LiDAR improves spatial placement; it does not recognize the book.

The displayed match score and content-overlap value are model scores, not calibrated probabilities. Ratings in the bundled catalog are demonstration values, not live reader reviews.

## Implemented use cases

- **Identify and understand:** scan a known cover or spine title and show an AR information card.
- **Discover:** receive explainable recommendations under three different ranking objectives.
- **Admin mapping:** create an AR room, define shelf rows and aisle stops, assign book positions, and save the map for later sessions.
- **Search and navigate:** search book details and follow the assigned route to an outlined shelf row after room alignment.
- **Find a recommendation:** follow a mapped recommendation to its shelf, then visually check its title. Unmapped recommendations use live title search.
- **Compare:** scan a second title and compare ratings, genres, shared themes, and TF-IDF content overlap.

## Data-backed future use cases

These should only be added when their required data exists:

- **Cover-image recognition:** train and evaluate a Core ML classifier using labeled covers, spines, lighting conditions, viewing angles, occlusions, and unknown-book negatives.
- **Exact edition detection:** add ISBN data and run Vision barcode recognition beside OCR.
- **Shelf audit and misplaced-book detection:** build on the saved assignments with call numbers and continuous multi-book scanning.
- **Personalized discovery:** learn from explicit likes or reading history with local storage and clear privacy controls; twelve demo books are not enough to evaluate personalization.
- **Accessible guidance:** add spoken results and haptics, then evaluate with the intended users.

For evaluation, report recognition top-1 accuracy, unknown-book false accepts, recognition latency, AR anchor error/drift, recommendation relevance/diversity, task completion time, and wrong-book selections. AR and LiDAR metrics require testing on the physical iPhone.

## Regenerate the Xcode project

The checked-in `.xcodeproj` is generated from `project.yml`:

```sh
xcodegen generate
```

The app target's existing signing Team is preserved in `project.yml`. Change it to your own Team when using another Apple Account.

## Test

```sh
xcodebuild test \
  -project ARSmartLibrary.xcodeproj \
  -scheme ARSmartLibrary \
  -derivedDataPath /tmp/ARSmartLibrary-build \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Build output is kept outside the project folder to avoid Finder metadata signing errors when the workspace is synced through iCloud Drive. If this simulator is unavailable, select an installed iPhone simulator in Xcode.

ARKit scene depth and LiDAR must be tested on the physical iPhone; Simulator only verifies the build and non-hardware logic.

Validated on October 12, 2026 with Xcode 16.2 and the iPhone 16 Pro Simulator running iOS 18.3: all 109 automated tests passed. The white arrow was visually checked in a separate Simulator preview at forward, right, and behind bearings and in a compact layout; real-room motion still needs the physical-device checks below. Custom-book creation, search, persistence across app relaunch, duplicate warnings, and cancellation with unsaved details were checked in Simulator. Catalog details and reading-status persistence were also checked in the previous build. Physical-device acceptance below remains required before claiming real-room accuracy.

### Physical-device acceptance checks

- Create two shelf rows with different routes, assign books, save, force-quit, and reopen near the entrance. Verify outlines return to the same rows only after alignment.
- Search for an assigned title/author/topic; visit every recorded stop and verify the correct row and slot label at arrival.
- Move away after arrival; the display must return to approach guidance. End directions and verify ordinary OCR scanning resumes.
- Cover the camera, turn quickly, and background/resume the app. Directions must disappear while tracking is unavailable and return after alignment without changing shelf positions.
- After backgrounding or interrupting the app, resume with the camera already steady. Verify scanning and book markers recover without needing to deliberately disturb tracking.
- Enter room, shelf or book-location details without submitting them. Done must ask before discarding the form, and swipe dismissal must keep it open. Create space and Record route must still hand off to the camera.
- Launch in another room. Directions must stay unavailable until the saved room is recognized.
- Reassign a book, remove a shelf, and remove the final shelf. Save each change, restart, and verify assignments/removals persisted.
- Change shelf contents and lighting, then record alignment success rate, shelf-position error, route completion time, wrong-row choices, and OCR false accepts. The current tests do not establish real-room accuracy.
