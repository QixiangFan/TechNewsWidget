# TechNews Widget

[English](#english) | [中文](#中文)

## English

A native macOS desktop widget (WidgetKit) and companion app for the latest tech news from Chinese and English tech media, Hacker News and GitHub Trending. Each story comes with the outlet's own summary and picture. No AI summaries, and a small on-disk cache.

> **Status: work in progress.** The data layer (`NewsKit`), the macOS app and the configurable widget work. Build instructions and screenshots are coming.

### Widget

The widget comes in all four desktop sizes. Edit a widget to choose its category and its style:

- **Headlines & Images** (default): pictures, summaries and a lead story. The small size shows one story over its photo, the medium size two stories, the large size a lead story and three more, and the extra-large size a lead story and four more. Summaries appear wherever there is room for them.
- **Headlines Only**: as many titles as fit (3, 6, 8 or 16 per page).

The ‹ and › buttons in the header turn to the previous and next page, wrapping around at either end, and clicking a story opens it in your browser. Stories without a picture show the outlet's monogram, the Hacker News category shows each story's rank, and GitHub stories show the owner's avatar. When macOS draws widgets in its monochrome or tinted style (for example while another app is in front), titles move off the photos so they stay legible.

### App

The app lays out the same news as a magazine front page: a lead story across the top and a grid of cards below. ⌘1–⌘5 switch categories and ⌘R refreshes the window and makes the widgets download fresh headlines too. Right-click a card to copy or share its link. Closing the window quits the app; the widgets keep updating on their own.

### Settings

Open Settings with ⌘, or the gear button in the toolbar.

- **General**: open TechNews at login; light, dark or system appearance; how often news is refreshed (every 30 minutes to 8 hours, 2 hours by default), which applies to the widgets and the open window; when the widgets last updated, with an **Update Now** button.
- **Content**
  - **Widget Sources**: turn individual sources on or off for the widgets, for example to leave Hacker News and GitHub out of the "All" mix. The app window always shows every source. A widget whose category has every source turned off says so.
  - **Muted Words**: hide stories whose title or summary mentions a word, in the widgets and in the window. English words match whole words (and their plural), so "AI" hides "AI chips" and "苹果发布AI新功能" but not "said" or "OpenAI"; Chinese words match anywhere.
- **Storage**: how much space the widget cache takes (headlines and pictures), and a button to clear it.

The app and the widget share these settings and the widget's cache through an App Group, `<Team ID>.com.qixiangfan.TechNews` (see the `.entitlements` files). The code reads the group from its own entitlements, so building with a different team needs no code changes.

### Sources

| Category | Sources |
|---|---|
| Chinese media | IT之家, 少数派, 爱范儿, 极客公园 (RSS) |
| English media | The Verge, Ars Technica (RSS / Atom); TechCrunch ([WordPress REST API](https://developer.wordpress.org/rest-api/), which includes featured images, with its RSS feed as a fallback) |
| Hacker News | Front page via the [Algolia HN API](https://hn.algolia.com/api) |
| GitHub | [Trending](https://github.com/trending) (daily), with the GitHub search API as a fallback |

Summaries and pictures come from the sources themselves: the feed's description or the article's first paragraphs (with datelines, bylines, "read more" links and newsletter plugs removed), and the article's lead image. 少数派 and Hacker News provide no pictures, and Hacker News link posts have no summary.

Sources are listed in [`NewsKit/Sources/NewsKit/NewsSource.swift`](NewsKit/Sources/NewsKit/NewsSource.swift). To add or remove one, edit that list.

### Design

- All sources are fetched concurrently with an 8 s timeout. If one source fails, the others still show.
- A category's headlines are interleaved round-robin, so every source appears near the top.
- **Small cache.** Each category is one JSON file, overwritten on every refresh. It holds at most 60 items, with titles truncated to 120 characters and summaries to 100, and is hard-capped at 64 KB. In practice all five files together take about 75 KB.
- **Small thumbnails.** The widget only downloads pictures for the page on screen and asks the image host for a resized copy, so a 4 MB original arrives as about 17 KB. Thumbnails are stored as JPEGs of at most 320 px, typically 5–20 KB each; the lead story of the large sizes gets a sharper 640 px copy, typically about 30 KB. The folder is capped at 300 KB and drops the oldest first. Altogether the widget's cache stays under about 400 KB.
- Networking uses an ephemeral `URLSession` with no `URLCache`, so feeds and images are never written to disk, apart from the thumbnails above. The app keeps pictures in memory only.
- Cache files and thumbnails older than 3 days (or unreadable) are deleted on every widget refresh, including those of categories no widget shows any more.
- The cache lives in the App Group's container, so the app's settings can show its size and clear it. Each file remembers which sources it was downloaded from, so turning a source on or off makes the widget download again.

All limits live in [`NewsKit/Sources/NewsKit/NewsCache.swift`](NewsKit/Sources/NewsKit/NewsCache.swift).

### Try the data layer

Requires Swift 5.10+ (Xcode or the Command Line Tools) on macOS 14+.

```sh
cd NewsKit
swift run newsdump                     # summary of every source plus the cache size per category
swift run newsdump hn                  # every item from one source, with summaries and image URLs
                                       # (ithome, sspai, ifanr, geekpark, verge, techcrunch, ars, hn, github)
swift run newsdump verge --thumbnails  # also download that source's thumbnails and print their sizes
swift test                             # offline parser, cache and thumbnail tests
```

### License

[MIT](LICENSE)

---

## 中文

一个 macOS 原生桌面小组件（WidgetKit）和配套 App，显示最新的科技资讯。来源包括中文科技媒体、英文科技媒体、Hacker News 和 GitHub Trending。每条资讯都带媒体自己写的摘要和配图，不做 AI 摘要，本地缓存很小。

> **状态：开发中。** 数据层（`NewsKit`）、macOS App 和可配置的小组件都已可用，编译说明和截图稍后补充。

### 小组件

支持桌面上的全部四种尺寸。编辑小组件时可以选择分类和样式：

- **图文**（默认）：图片、摘要和头条。小号显示一条资讯，标题叠在照片上；中号显示两条；大号显示一条头条和另外三条；超大显示一条头条和另外四条。空间允许时，资讯下方会显示摘要。
- **仅标题**：放下尽可能多的标题（每页 3、6、8 或 16 条）。

点标题栏里的 ‹ 和 › 前后翻页，翻到头会接着从另一端开始；点资讯会在浏览器中打开。没有配图的资讯显示媒体的字标，Hacker News 分类显示每条的排名，GitHub 的资讯显示作者头像。macOS 用单色或着色样式显示小组件时（例如正在使用别的 App），标题会移到照片外面，保证看得清。

### 主 App

App 把同样的资讯排成杂志首页：顶部是一条头条大图，下面是卡片网格。⌘1–⌘5 切换分类，⌘R 刷新窗口，同时让小组件重新下载资讯。右键点按卡片可以拷贝或分享链接。关闭窗口即退出 App，小组件会自己继续更新。

### 设置

按 ⌘, 或点工具栏里的齿轮按钮打开设置。

- **通用**：登录时打开 TechNews；外观（跟随系统、浅色、深色）；刷新间隔（30 分钟到 8 小时，默认 2 小时），同时适用于小组件和打开着的窗口；小组件上次更新的时间，以及“立即更新”按钮。
- **内容**
  - **小组件新闻来源**：单独打开或关闭小组件里的每个来源，比如让“全部”分类里不出现 Hacker News 和 GitHub。App 窗口始终显示全部来源。如果某个小组件所选分类的来源全被关闭，小组件上会给出提示。
  - **屏蔽词**：标题或摘要里含有屏蔽词的资讯，在小组件和窗口里都不显示。英文按整个单词匹配（包括复数），所以屏蔽“AI”会隐藏“AI chips”和“苹果发布AI新功能”，但不会隐藏“said”或“OpenAI”；中文词在任何位置出现都算。
- **存储空间**：小组件缓存占用的空间（新闻列表和图片），以及清除缓存的按钮。

App 和小组件通过 App Group（`<Team ID>.com.qixiangfan.TechNews`，见 `.entitlements` 文件）共享这些设置和小组件的缓存。代码从自身的 entitlements 里读取 App Group 名称，所以换成别的开发者团队编译时不用改代码。

### 资讯来源

| 分类 | 来源 |
|---|---|
| 中文媒体 | IT之家、少数派、爱范儿、极客公园（RSS） |
| 英文媒体 | The Verge、Ars Technica（RSS / Atom）；TechCrunch（[WordPress REST API](https://developer.wordpress.org/rest-api/)，带封面图，拿不到时改用 RSS） |
| Hacker News | 首页，通过 [Algolia HN API](https://hn.algolia.com/api) 获取 |
| GitHub | [Trending](https://github.com/trending) 日榜，拿不到时改用 GitHub 搜索 API |

摘要和图片都来自各个来源自己：订阅里的简介或正文开头几段（去掉电头、署名、“查看全文”链接和公众号推广），以及文章的首图。少数派和 Hacker News 没有配图，Hacker News 的链接帖没有摘要。

来源清单在 [`NewsKit/Sources/NewsKit/NewsSource.swift`](NewsKit/Sources/NewsKit/NewsSource.swift)，增删来源改这个列表就行。

### 设计

- 所有来源并发请求，每个超时 8 秒；某个来源失败时，其他来源照常显示。
- 同一分类里的多个来源轮流穿插排序，保证每个来源都能出现在靠前的位置。
- **缓存很小。** 每个分类只存一个 JSON 文件，每次刷新整体覆盖；最多 60 条，标题截断到 120 字，摘要截断到 100 字，单个文件不超过 64 KB。实际五个文件合计约 75 KB。
- **缩略图很小。** 小组件只下载当前页的图片，并请图床先把图缩小，一张 4 MB 的原图下载下来只有约 17 KB。缩略图存成最长边不超过 320 像素的 JPEG，一般每张 5–20 KB；大号和超大的头条用更清晰的 640 像素版本，一般约 30 KB。整个目录不超过 300 KB，超出时先删最旧的。小组件的全部缓存合计不超过约 400 KB。
- 网络请求使用 ephemeral `URLSession`，并关闭了 `URLCache`，除了上面的缩略图，订阅原文和图片都不会写入磁盘。App 里的图片只放在内存中。
- 每次小组件刷新时，都会删除超过 3 天或已损坏的缓存文件和缩略图，包括已经没有小组件在用的分类。
- 缓存放在 App Group 的共享目录里，所以 App 的设置能显示缓存大小并清除缓存。每个缓存文件都记着自己是从哪些来源下载的，打开或关闭来源后，小组件会重新下载。

所有上限都定义在 [`NewsKit/Sources/NewsKit/NewsCache.swift`](NewsKit/Sources/NewsKit/NewsCache.swift)。

### 试用数据层

需要 macOS 14 或更高版本，以及 Swift 5.10 或更高版本（装了 Xcode 或 Command Line Tools 即可）。

```sh
cd NewsKit
swift run newsdump                     # 所有来源概况 + 每个分类的缓存大小
swift run newsdump hn                  # 某个来源的全部条目，含摘要和图片地址
                                       # （可选：ithome, sspai, ifanr, geekpark, verge, techcrunch, ars, hn, github）
swift run newsdump verge --thumbnails  # 同时下载这个来源的缩略图，并打印大小
swift test                             # 离线的解析、缓存和缩略图测试
```

### 许可证

[MIT](LICENSE)
