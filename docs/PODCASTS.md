> Note: the spike app and its dump files referenced below were removed from the repository.

# Hide podcasts / Hide Audible — DOM findings

Settings (General, independent, both default off): "Hide podcasts" (`AppSettings.hidePodcasts`, key `hidePodcasts`) and
"Hide Audible" (`AppSettings.hideAudible`, key `hideAudible`).
Script: `Sources/AmazonMusic/Resources/hideSections.js` (formerly hidePodcasts.js; all DOM knowledge in its single `RULES` object,
`RULES.sections.podcasts|audible`). API: `window.__amzHideSections.setEnabled('podcasts'|'audible', bool)`, `isEnabled(id)`, `rescan()`.
Marks elements with `data-amz-hide-<section>` so each toggle restores only its own elements.
Swift wiring: `HideSectionsScript` (Web/), `WebController.installHideSections/refreshHideSectionsScript/applyHideSections`.
Tests: `node tools/hidesections-test/hidesections.test.mjs` (mock DOM), `HideSectionsTests` (Swift).

## How it was investigated
The spike app (signed in, Safari UA, 2026-10-26) was temporarily extended (`spike/Sources/Spike/SpikeApp.swift`, env `SPIKE_DUMP=1` /
`SPIKE_VERIFY=1`) to load pages and dump an anonymised structure: tag, selected attributes (hrefs reduced to path patterns with ids
replaced by `:id`), ancestor chains, headings. No account names, emails or listening history were recorded. Output stayed in
`spike/podcast-dump.jsonl` and `spike/podcast-verify.jsonl` (spike dir only).
Sampled: `/home`, `/explore`, `/search/podcast`, `/search/jazz`, `/podcasts`.

## Findings (real page)
- The site is **react-native-web**: no custom elements and **no shadow DOM** (0 shadow hosts), so plain CSS/JS in the main document reaches everything.
  Class names are hashed atoms (`css-g5y9jx r-1loqt21 ...`): unusable. `data-testid` is a comma-separated list of component names
  (e.g. `HorizontalItem,SearchResultsWidget_TopResults_PodcastShowItem`), so use `*=` substring matches.
- Nav: there is no sidebar; a top bar `header > nav` has `button[data-testid="TopNavBar_PodcastTab"][aria-label="Podcasts"]`.
  The search input (`SearchBox_TextInput`, aria-label "Search Music and Podcasts") and a `/search` link also mention podcasts; they are left alone.
- Search filter pills: `button[data-testid*="SearchResultsTypeFilter_Pill_podcast"]` ("Podcasts") and `..._Pill_podcastEpisode` ("Podcast Episodes").
- Search result shelves: root `div[data-testid="SearchResultsWidget_PodcastShow"]` and `SearchResultsWidget_PodcastEpisode`; heading is
  `h1[role=heading][aria-label="Podcasts"] > h4[data-testid="WidgetHeader_Primary_SearchResults_ResultsHeader"]`.
- Top Results: items `HorizontalItem,SearchResultsWidget_TopResults_PodcastShowItem` / `..._PodcastEpisodeItem`, wrapped in `div[data-testid="CarouselItem"]`.
- Cards/links: `a[href^="/podcasts/<id>/<id>"]` (also `/podcasts/<id>`). Other link patterns seen: `/albums/:id`, `/artists/:id`, `/playlists/:id`, `/release/:id`, `/tracks/:id`.
- Shelf headings are `h4[role=heading]`; carousel entries are `CarouselItem` divs.
- Podcast landing page `/podcasts` shows "Top Podcasts By Category" and show links.

## What the script does
Hides via a `data-amz-hide-podcasts` attribute (+ `display:none !important` rule), applied by (per section, all in `RULES.sections`): direct testid selectors (nav tab, pills,
search widgets), podcast cards (`CarouselItem`/`li` ancestor of a `/podcasts` link or `TopResults_Podcast*` item), and shelves found by
heading text (`Podcast(s)`, `Podcasten`, `ポッドキャスト`; shelf = highest ancestor holding exactly one heading, never `main/nav/header/#root`
or anything containing an `<input>`). A debounced MutationObserver re-applies it. Disabling removes every attribute and the `<style>`.
Not hidden: the player/footer, anything containing playing media, and the content of `/podcasts*` pages (only nav/pills are hidden there,
otherwise the page would be blank).
Live toggle: `WebController.observeSettings` (tracks hidePodcasts + hideAudible) -> `refreshHideSectionsScript()` (re-registers the user script with the new initial flags for
future loads) + `applyHideSections()` (`setEnabled` per section on the current page); also applied from `didFinish`.

## Verified against the real page (spike, script injected after load, enable then disable)
| Page | Result |
|---|---|
| `/home` | nav tab hidden then restored. No podcast shelf exists on this account's Home, so shelf/heading logic there is **unverified on real Home**. |
| `/search/jazz` | 29 elements hidden: nav tab, 2 pills, 2 widgets, 22 podcast cards; 0 podcast links/pills/widgets visible after; other headings (Songs, Albums...) intact; all restored after disable. |
| `/search/podcast` | 33 hidden incl. 26 cards; 0 testid-matched podcast elements visible; "Top Results"/Albums/Songs etc. intact; restored. |
| `/podcasts` | only nav tab hidden (by design); content kept. |

## Unverified / known gaps
- Script was verified injected *after* load via `evaluateJavaScript`; the documentStart WKUserScript path in the real app was not exercised
  against the live page (build + unit tests only). Do the QA.md check.
- `/explore` rendered almost nothing (13 elements) in the headless sample: Browse/Explore page not sampled. Home shelves for podcasts not seen.
- Localised headings/regions other than en are heuristic only.
- Mixed-content shelves (e.g. a "Recommended" shelf holding a few podcast cards) have only the podcast cards removed, which may leave a gap.
- Search results may leave a podcast row that is not a link (none observed).
- If Amazon renames testids (`TopNavBar_PodcastTab`, `SearchResultsWidget_Podcast*`, `SearchResultsTypeFilter_Pill_podcast*`) update `RULES`.

## Audible (audiobooks) — findings (spike, signed in, 2026-10-27, anonymised)
Spike temporarily extended again (`SPIKE_DUMP=1` / `SPIKE_VERIFY=1`; dumps `spike/audible-dump.jsonl`, `audiobook-dump.jsonl`, `audible-verify.jsonl`, spike dir only).
Sampled `/home`, `/search/audible`, `/search/audiobook`, `/search/jazz`, `/audiobooks`.
- **The "Audible" tab in the top bar is the Audiobook tab**: `button[data-testid="TopNavBar_AudiobooksTab"][aria-label="Audiobook"]` (no `href`; it is a button).
  Nav order: Home, Music, Audiobooks, Podcasts, Library (`TopNavBar_HomeTab|MusicTab|AudiobooksTab|PodcastTab|LibraryTab`), plus `TopNavBar_Menu`.
  Nothing in the nav says "Audible" literally.
- Search: filter pill `...SearchResultsTypeFilter_Pill_audiobook` ("Audiobooks"); shelf root `div[data-testid="SearchResultsWidget_Audiobook"]` with `h4` heading "Audiobooks";
  top result `HorizontalItem,SearchResultsWidget_TopResults_AudiobookItem` (+ `_PlayableImage`, `_Metadata`, `ItemMetadata_Label_Audiobook`, `IconButton,AudiobookHorizontal_ContextMenu`).
- Audiobook cards link to opaque `/<id>/<id>` paths (not distinguishable by href), so they are recognised only via testids and shelf headings.
- `/audiobooks` (browse page): hero `audiobook-browse-hero`, shovelers `audiobook-editorial-shoveler-N` with items `...-item-N`, headings such as
  "Only From Audible", "Your Next Favorite Listen", "New Releases", "Trending" (generic titles, so on `/audiobooks` content is kept like `/podcasts`; only nav/pills are hidden).
- The word "Audible" also appears as a normal artist/playlist name in search results (`SearchResultsWidget_TopResults_ArtistItem_*`, aria-label "Audible") and in podcast titles
  ("... presented by Audible"). These are deliberately **not** hidden (matching is by testid and shelf headings only, never card text).
- `/home` of this account: no audiobook shelf, only the nav tab. No shadow DOM.

### Audible verified on the real page (spike; script injected after load via `evaluateJavaScript`, sections toggled audible -> +podcasts -> podcasts only -> off)
| Page | Result |
|---|---|
| `/home` | Audible on: `TopNavBar_AudiobooksTab` hidden, Podcasts tab still visible; both on: both hidden; podcasts only: only podcasts hidden; all off: all 5 tabs restored. |
| `/search/jazz` | Audible on: tab, "Audiobooks" pill and `SearchResultsWidget_Audiobook` hidden (4 marks incl. heading), podcast pills (2) and widgets (2) still visible. Both on: all of them gone (31 podcast marks, 4 audible). Podcasts only: audiobook items stay visible. Off: everything restored; headings intact. |
| `/audiobooks` | Only the nav tab hidden (content kept by design; 10 `audiobook-*` roots remain visible). |
Not verified: the documentStart WKUserScript path in the live app (use QA.md), localised headings, an audiobook shelf on Home (this account has none),
`TopResults_Audiobook` top-result hiding on the real page (testids observed on `/search/audiobook` in the dump but the verify run did not sample that URL; covered by mock tests only).

## Audible icon still visible + "Get App" — findings (spike, signed in, 2026-10-27, anonymised)
Top nav dumped on the real page at window width 1147 and 800 (identical structure; the nav is icon-only at both, buttons 34px wide at x=186/244/302/360/418):

| # | tag | data-testid | aria-label | href | svg | text |
|---|-----|-------------|-----------|------|-----|------|
| 1 | button | `TopNavBar_HomeTab` | Amazon Music Home | – | yes | – |
| 2 | button | `TopNavBar_MusicTab` (headphones) | Music | – | yes | – |
| 3 | button | `TopNavBar_AudiobooksTab` (**the Audible-logo glyph**) | Audiobook | – | yes (no `<title>`) | – |
| 4 | button | `TopNavBar_PodcastTab` | Podcasts | – | yes | – |
| 5 | button | `TopNavBar_LibraryTab` | Library | – | yes | – |
| – | button | `Button,GetAppButton` (right side) | Get App | – | no | "Get App" |

- **Conclusion:** the Audible-logo icon is the same element the old rule already matched (#3). No separate Audible tab, no href, no late async element observed. The icon stayed because **Hide Audible defaulted OFF**. Fix: `hideAudible` now defaults to **true when the user never set it** (`defaults.object(forKey:) == nil`); an explicit choice is kept. `hidePodcasts` default unchanged (off).
- Hardening in hideSections.js (v3): testid matching is case-insensitive (`TopNavBar_Audiobook` / `TopNavBar_Audible`), plus a control scan in nav scope (`TopNavBar*`, header, nav, banner) matching aria-label / title / svg `<title>`/aria-label / short text (<=20 chars) against audible/audiobook words (localised), and `href` `/audible`, `/audiobook(s)`. The existing debounced MutationObserver re-hides late-rendered nav.
- **getApp section** (new, `hideGetApp`, default true when unset): testid `*GetApp*` / `*DownloadApp*` / `*InstallApp*` (case-insensitive) and any button/link whose aria-label/title/own text is <=20 chars and exactly "Get App", "Get the app", "Download app", de/fr/es/it/pt/ja variants. Only the control itself is hidden; player (protected selectors), search and account buttons are never matched. No banner/modal promo was seen on the real page (home, signed in), so none is covered beyond the same text/testid rules.
- Verified on the **real page** (spike, script injected via evaluateJavaScript, audible+getApp on): visible `TopNavBar_*`+GetApp went from 5 tabs + Get App to Home, Music, Podcast, Library only; toggled off -> all restored; on again -> hidden. Window screenshot: nav shows house, headphones, (gap), podcast, library; search + avatar remain; Get App absent. The "late-rendered nav" case (an injected `aria-label="Audible"` button with svg title, appended after enable) was a **synthetic** element on the real page; it was hidden by the observer.

## Home page banner (`homeBanner`) — findings (spike, signed in, 2026-10-27, anonymised)
Spike `SPIKE_PROBE=1` eval loop (temporary, removed). `/` at ~1100px: the top of `[data-testid="Page"] > BrowseHome_RecommendationsList` is a ~300px hero carousel (here an "AD-FREE PODCAST" promo, so podcasts/ads do appear there). The banner **was present** on the account when tested.
- Stable signal: `data-testid="BrowseHome_Top_Recommender"` (children `BrowseHome_TopRecommender_Artwork`, `TopRecommender_*`, `PageHeaderMetadata_*`, `pageHeaderPlay_Play_Button`). No role/aria. The regular shelves are separate siblings in the list (`Box,WidgetHeader,<Name>` + `Carousel`), not matched.
- Structure: list > [wrapper (1 child) > wrapper (1 child) > Top_Recommender] + shelf blocks. The rule marks the outermost single-child wrapper (stops when the parent has >1 child), so no padding/margin gap stays.
- Only active when `location.pathname` is `/` or `/home`; leaving the route removes the mark (unhide). Re-evaluated via `history.pushState/replaceState`, `popstate`, `hashchange` hooks plus the existing MutationObserver. Hiding is CSS `display:none !important` via `[data-amz-hide-homeBanner]`.
- Live verification (script injected after load): hidden=1, root height 0, first shelf header moved to the top (y=64, same as list top: no gap); nav, Get App, search, player untouched. Library tab: unhidden (0 marks); Home tab: re-hidden (1); `setEnabled('homeBanner', false)`: banner back (300px).
- Unverified: other banner variants (only one hero seen; other accounts/ad types may use other testids), pre-hydration flash (no CSS-only rule: JS applies within ~150ms of render).
