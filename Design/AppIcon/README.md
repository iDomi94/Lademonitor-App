# App-Icon „Säule lädt Auto“

Quelldateien des App-Icons: eine Ladesäule mit Ring-Display, per Kabel mit
einem Auto (von oben) verbunden, auf dem eine Batterie den Ladestand zeigt.

| Datei | Zweck |
| --- | --- |
| `lademonitor-icon-light.svg` | Standard-Icon (Hintergrund #3A4A6B → #1F2A44) |
| `lademonitor-icon-dark.svg` | Dark-Mode-Variante |
| `lademonitor-icon-tinted.svg` | Getönte Variante (Graustufen, iOS färbt ein) |
| `lademonitor-foreground.svg` / `.png` | Nur das Motiv ohne Hintergrund, für Icon Composer |

Die PNGs im Asset-Katalog (`Lademonitor/Assets.xcassets/AppIcon.appiconset`)
sind aus diesen SVGs in 1024 × 1024 px gerendert, quadratisch ohne Maske.

Für Liquid Glass (iOS 26) lässt sich das Motiv in Icon Composer in Ebenen
aufteilen: Hintergrund als Verlauf, darüber Säule, Auto und das türkise Kabel
mit Ring und Batterie als Akzent-Ebene.
