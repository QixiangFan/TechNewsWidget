# TechNews Widget

[English](#english) | [中文](#中文)

## English

A native macOS desktop widget (WidgetKit) that shows the latest tech headlines from Chinese and English tech media, Hacker News and GitHub Trending. Headlines only, no AI summaries, and a very small on-disk cache.

> **Status: work in progress.** The data layer (`NewsKit`) is done and tested. The macOS app and widget are next.

### Sources

| Category | Sources |
|---|---|
| Chinese media | IT之家, 少数派, 爱范儿, 极客公园 (RSS) |
| English media | The Verge, TechCrunch, Ars Technica (RSS / Atom) |
| Hacker News | Front page via the [Algolia HN API](https://hn.algolia.com/api) |
| GitHub | [Trending](https://github.com/trending) (daily), with the GitHub search API as a fallback |

Sources are listed in [`NewsKit/Sources/NewsKit/NewsSource.swift`](NewsKit/Sources/NewsKit/NewsSource.swift). To add or remove one, edit that list.

### Design

- All sources are fetched concurrently with an 8 s timeout. If one source fails, the others still show.
- A category's headlines are interleaved round-robin, so every source appears near the top.
- **Small cache.** Each category is one JSON file, overwritten on every refresh. It holds at most 60 items, with titles truncated to 120 characters, and is hard-capped at 64 KB. In practice the whole cache is about 40 KB.
- Networking uses an ephemeral `URLSession` with no `URLCache`, so raw feeds are never written to disk.
- Cached headlines older than 3 days are not shown.

All limits live in [`NewsKit/Sources/NewsKit/NewsCache.swift`](NewsKit/Sources/NewsKit/NewsCache.swift).

### Try the data layer

Requires Swift 5.10+ (Xcode or the Command Line Tools) on macOS 14+.

```sh
cd NewsKit
swift run newsdump          # summary of every source plus the cache size per category
swift run newsdump hn       # every item from one source (ithome, sspai, ifanr, geekpark, verge, techcrunch, ars, hn, github)
swift test                  # offline parser and cache tests
```

### License

[MIT](LICENSE)

---

## 中文

一个 macOS 原生桌面小组件（WidgetKit），显示最新的科技资讯标题。来源包括中文科技媒体、英文科技媒体、Hacker News 和 GitHub Trending。只显示标题，不做 AI 摘要，本地缓存非常小。

> **状态：开发中。** 数据层（`NewsKit`）已经完成并通过测试，macOS App 和小组件正在开发。

### 资讯来源

| 分类 | 来源 |
|---|---|
| 中文媒体 | IT之家、少数派、爱范儿、极客公园（RSS） |
| 英文媒体 | The Verge、TechCrunch、Ars Technica（RSS / Atom） |
| Hacker News | 首页，通过 [Algolia HN API](https://hn.algolia.com/api) 获取 |
| GitHub | [Trending](https://github.com/trending) 日榜，拿不到时改用 GitHub 搜索 API |

来源清单在 [`NewsKit/Sources/NewsKit/NewsSource.swift`](NewsKit/Sources/NewsKit/NewsSource.swift)，增删来源改这个列表就行。

### 设计

- 所有来源并发请求，每个超时 8 秒；某个来源失败时，其他来源照常显示。
- 同一分类里的多个来源轮流穿插排序，保证每个来源都能出现在靠前的位置。
- **缓存很小。** 每个分类只存一个 JSON 文件，每次刷新整体覆盖；最多 60 条，标题截断到 120 字，单个文件不超过 64 KB。实际全部缓存合计约 40 KB。
- 网络请求使用 ephemeral `URLSession`，并关闭了 `URLCache`，订阅原文不会写入磁盘。
- 超过 3 天的缓存不再显示。

所有上限都定义在 [`NewsKit/Sources/NewsKit/NewsCache.swift`](NewsKit/Sources/NewsKit/NewsCache.swift)。

### 试用数据层

需要 macOS 14 或更高版本，以及 Swift 5.10 或更高版本（装了 Xcode 或 Command Line Tools 即可）。

```sh
cd NewsKit
swift run newsdump          # 所有来源概况 + 每个分类的缓存大小
swift run newsdump hn       # 某个来源的全部条目（可选：ithome, sspai, ifanr, geekpark, verge, techcrunch, ars, hn, github）
swift test                  # 离线的解析和缓存测试
```

### 许可证

[MIT](LICENSE)
