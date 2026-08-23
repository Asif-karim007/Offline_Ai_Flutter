# App icon PNGs

`Contents.json` next to this file lists the exact filenames and pixel sizes Xcode expects.
**No PNGs are committed** — they are binary assets, and a fabricated one is worse than a
missing one.

Until you add them, the asset catalog compiles with "unassigned children" warnings, the app
shows the default blank icon, and App Store validation rejects the archive for the missing
1024×1024 marketing icon.

Generate them one of two ways:

* Run `flutter create --platforms=ios --org net.salebee --project-name offline_ai_chat .`
  from the project root (you have to do this anyway to get `Runner.xcodeproj` — see
  `ios/README.md`). It drops the stock Flutter icon set in here with these exact names.
* Or produce your own artwork and export at these sizes (points × scale = pixels):

| Filename | Pixels |
|---|---|
| `Icon-App-20x20@1x.png` | 20 |
| `Icon-App-20x20@2x.png` | 40 |
| `Icon-App-20x20@3x.png` | 60 |
| `Icon-App-29x29@1x.png` | 29 |
| `Icon-App-29x29@2x.png` | 58 |
| `Icon-App-29x29@3x.png` | 87 |
| `Icon-App-40x40@1x.png` | 40 |
| `Icon-App-40x40@2x.png` | 80 |
| `Icon-App-40x40@3x.png` | 120 |
| `Icon-App-60x60@2x.png` | 120 |
| `Icon-App-60x60@3x.png` | 180 |
| `Icon-App-76x76@1x.png` | 76 |
| `Icon-App-76x76@2x.png` | 152 |
| `Icon-App-83.5x83.5@2x.png` | 167 |
| `Icon-App-1024x1024@1x.png` | 1024 |

All must be opaque PNGs with no alpha channel and no rounded corners — iOS applies the mask
itself, and an alpha channel in the marketing icon is an automatic App Store rejection.
