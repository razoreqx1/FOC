# Installation and updates

## Steam Workshop installation

1. Open [Fleet Operations Command on Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3793624775).
2. Select **Subscribe**.
3. Allow Steam to finish downloading the extension.
4. Start X4: Foundations.
5. Open **Extensions** and enable **Fleet Operations Command** if it is not already enabled.

## Manual installation

1. Close X4: Foundations normally.
2. Download [`FOC_v154_GA.zip`](../dist/FOC_v154_GA.zip).
3. Extract the archive.
4. Copy the contained lowercase `jk_foc` folder into the X4 `extensions` directory.

The final path must look like:

```text
X4 Foundations/extensions/jk_foc/content.xml
```

Do not add another directory between `extensions` and `jk_foc`.

## Updating a manual installation

1. Close X4 normally.
2. Preserve your previous `jk_foc` folder if you want a manual rollback copy.
3. Replace the complete old `jk_foc` folder with the complete folder from the new release.
4. Do not mix files from different versions.

## Removing FOC

Unsubscribe from the Workshop item or, for a manual installation, close X4 and remove the `jk_foc` folder. FOC does not add custom ships, sectors, wares, or stations required to load a save. Saved FOC planning data is useful only while the extension is present.

## Verifying the archive

The v1.54 GA archive SHA-256 is:

```text
2660EF2952CB4F995534832FE2F35BD280FF3A4C39E55759670D769E0C129F5A
```


## Version 1.54 saved carrier settings

After installing the complete v1.54 package with X4 closed, load your game and choose the intended carrier in **Fleets -> Strategic Ops -> Carrier Air Wings**. Check **Saved wing** for the exact carrier/group profile. A dropdown change alone is not a saved setting. Use Apply deliberately, check readback, and save the game normally.

The archive link and checksum above identify the v1.54 distribution.
