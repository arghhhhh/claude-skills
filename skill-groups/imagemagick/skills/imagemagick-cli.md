---
version: 1.0.0
---

# ImageMagick CLI Skill

Use this skill to manipulate images via the `magick` CLI (ImageMagick 7+).

## Setup

- **Binary**: `magick` (ImageMagick 7+ unified command)
- **Verify**: `magick --version`
- **Download**: https://imagemagick.org/script/download.php
- **Not installed?**
  - Windows: `winget install ImageMagick.ImageMagick` or download from https://imagemagick.org/script/download.php#windows
  - macOS: `brew install imagemagick` or download from https://imagemagick.org/script/download.php#macosx
  - Linux: `sudo apt install imagemagick`

## Important Notes

- ImageMagick 7 uses `magick` as the single entry point. Legacy v6 commands (`convert`, `identify`, `composite`, `montage`, `mogrify`) still work as `magick convert`, `magick identify`, etc.
- **`mogrify` edits files in-place** — always warn the user or work on copies.
- Use `magick` (not `convert`) to avoid conflicts with Windows `convert.exe` (disk utility).
- Quote file paths that contain spaces.
- For batch operations on many files, prefer `mogrify` over looping `magick` for performance.

## Identify / Inspect

```bash
magick identify image.png                    # Basic info (format, dimensions, depth, size)
magick identify -verbose image.png           # Full metadata (colorspace, compression, EXIF, etc.)
magick identify -format "%wx%h" image.png    # Just dimensions (e.g., "1920x1080")
magick identify -format "%[EXIF:*]" photo.jpg  # All EXIF data
magick identify -format "%m %wx%h %b" image.png  # Format, dimensions, file size
```

### Useful format specifiers

| Specifier | Meaning |
|-----------|---------|
| `%w` | Width (pixels) |
| `%h` | Height (pixels) |
| `%m` | Format (PNG, JPEG, etc.) |
| `%b` | File size |
| `%z` | Bit depth |
| `%[colorspace]` | Colorspace |
| `%[EXIF:DateTime]` | EXIF date |

## Format Conversion

```bash
magick input.png output.jpg                  # PNG to JPEG
magick input.bmp output.webp                 # BMP to WebP
magick input.jpg output.pdf                  # Image to PDF
magick input.svg output.png                  # SVG to raster
magick *.jpg output.pdf                      # Multiple images to multi-page PDF
magick input.gif[0] frame0.png               # Extract first frame of GIF
magick input.gif frames_%03d.png             # Extract all GIF frames
```

### Quality and compression

```bash
magick input.png -quality 85 output.jpg      # JPEG quality (1-100, default ~92)
magick input.png -quality 50 output.webp     # WebP quality
magick input.png -define png:compression-level=9 output.png  # Max PNG compression
magick input.png -strip output.jpg           # Remove all metadata (EXIF, ICC, etc.)
```

## Resize and Scaling

```bash
magick input.png -resize 800x600 output.png           # Fit within 800x600 (preserves aspect ratio)
magick input.png -resize 800x600! output.png           # Force exact size (distorts)
magick input.png -resize 800x600^ output.png           # Fill 800x600 (may overflow one dimension)
magick input.png -resize 50% output.png                # Scale to 50%
magick input.png -resize 800x output.png               # Width 800, auto height
magick input.png -resize x600 output.png               # Height 600, auto width
magick input.png -resize "800x600>" output.png         # Only shrink if larger
magick input.png -resize "800x600<" output.png         # Only enlarge if smaller
```

### Resize flags summary

| Flag | Behavior |
|------|----------|
| (none) | Fit within box, preserve aspect ratio |
| `!` | Force exact dimensions (may distort) |
| `^` | Fill box (crop overflow with `-gravity center -extent`) |
| `>` | Only shrink larger images |
| `<` | Only enlarge smaller images |

### Thumbnail (fast resize + strip metadata)

```bash
magick input.jpg -thumbnail 200x200 thumb.jpg
```

## Crop and Trim

```bash
magick input.png -crop 400x300+100+50 output.png      # Crop 400x300 starting at x=100,y=50
magick input.png -gravity center -crop 400x300+0+0 output.png  # Crop from center
magick input.png -trim output.png                      # Auto-trim whitespace/borders
magick input.png -trim -fuzz 10% output.png            # Trim with tolerance for near-white
magick input.png -shave 20x20 output.png               # Remove 20px from each edge
```

### Fill-crop (resize + crop to exact size)

```bash
magick input.png -resize 800x600^ -gravity center -extent 800x600 output.png
```

## Rotation and Flipping

```bash
magick input.png -rotate 90 output.png                 # Rotate 90 degrees clockwise
magick input.png -rotate -45 output.png                # Rotate 45 degrees counter-clockwise
magick input.png -rotate "90>" output.png              # Rotate only if wider than tall
magick input.png -auto-orient output.png               # Fix orientation from EXIF
magick input.png -flip output.png                      # Vertical mirror
magick input.png -flop output.png                      # Horizontal mirror
magick input.png -transpose output.png                 # Flip + rotate 90 CW
magick input.png -transverse output.png                # Flip + rotate 90 CCW
```

## Color and Adjustments

```bash
magick input.png -brightness-contrast 10x5 output.png  # Brightness +10%, contrast +5%
magick input.png -modulate 110,130,100 output.png       # Brightness 110%, saturation 130%, hue 100%
magick input.png -auto-level output.png                 # Auto stretch levels
magick input.png -auto-gamma output.png                 # Auto gamma correction
magick input.png -normalize output.png                  # Full-range normalize
magick input.png -equalize output.png                   # Histogram equalization
magick input.png -negate output.png                     # Invert colors
magick input.png -grayscale Rec709Luminance output.png  # Convert to grayscale
magick input.png -sepia-tone 80% output.png             # Sepia effect
magick input.png -colorspace sRGB output.png            # Convert colorspace
magick input.png -level 10%,90% output.png              # Adjust levels (black/white points)
magick input.png -gamma 1.5 output.png                  # Gamma correction
magick input.png -tint 40 output.png                    # Color tint
```

### Channel operations

```bash
magick input.png -channel R -evaluate set 0 +channel output.png   # Zero out red channel
magick input.png -channel RGB -negate +channel output.png          # Invert only RGB (keep alpha)
magick input.png -separate output_%d.png                           # Split into separate channels
```

## Effects and Filters

```bash
magick input.png -blur 0x3 output.png                  # Gaussian blur (radius x sigma)
magick input.png -gaussian-blur 0x5 output.png         # Explicit Gaussian
magick input.png -sharpen 0x2 output.png               # Sharpen
magick input.png -unsharp 0x5+1.5+0 output.png        # Unsharp mask (radius, sigma, amount, threshold)
magick input.png -edge 2 output.png                    # Edge detection
magick input.png -emboss 2 output.png                  # Emboss effect
magick input.png -charcoal 2 output.png                # Charcoal sketch
magick input.png -sketch 0x20+120 output.png           # Pencil sketch
magick input.png -oil-paint 4 output.png               # Oil painting
magick input.png -noise 3 output.png                   # Add noise
magick input.png -median 3 output.png                  # Median filter (denoise)
magick input.png -posterize 4 output.png               # Reduce to N color levels
magick input.png -vignette 0x40 output.png             # Vignette effect
magick input.png -swirl 90 output.png                  # Swirl distortion
magick input.png -implode 0.5 output.png               # Implode distortion
magick input.png -wave 10x100 output.png               # Wave distortion
magick input.png -motion-blur 0x12+45 output.png       # Motion blur (radius, sigma, angle)
magick input.png -radial-blur 10 output.png            # Radial/spin blur
magick input.png -shadow 60x4+2+2 output.png           # Drop shadow (opacity, sigma, x, y)
```

## Text and Annotations

```bash
# Simple text overlay
magick input.png -gravity south -fill white -pointsize 36 \
  -annotate +0+20 "Hello World" output.png

# Text with background box
magick input.png -gravity north -fill white -undercolor "#00000080" \
  -pointsize 24 -annotate +0+10 " Caption Text " output.png

# Specific font
magick input.png -font "Arial-Bold" -pointsize 48 -fill red \
  -gravity center -annotate +0+0 "DRAFT" output.png

# Text with stroke (outline)
magick input.png -font "Arial" -pointsize 40 \
  -stroke black -strokewidth 2 -fill white \
  -gravity center -annotate +0+0 "Outlined" output.png

# Multiline text
magick input.png -gravity center -pointsize 30 -fill white \
  -annotate +0+0 "Line 1\nLine 2\nLine 3" output.png
```

### List available fonts

```bash
magick -list font | head -60
```

## Compositing and Overlays

```bash
# Overlay one image on another
magick base.png overlay.png -gravity center -composite output.png

# Overlay with transparency
magick base.png overlay.png -gravity southeast -geometry +10+10 -composite output.png

# Watermark (semi-transparent overlay)
magick base.png watermark.png -gravity center -dissolve 30% -composite output.png

# Specific composite modes
magick base.png overlay.png -compose Multiply -composite output.png
magick base.png overlay.png -compose Screen -composite output.png
magick base.png overlay.png -compose Overlay -composite output.png

# Tile a pattern
magick -size 800x600 tile:pattern.png output.png
```

### Common compose modes

| Mode | Effect |
|------|--------|
| `Over` | Standard overlay (default) |
| `Multiply` | Darken (like multiply blend) |
| `Screen` | Lighten |
| `Overlay` | Contrast-enhancing blend |
| `Dissolve` | Transparency blend |
| `Difference` | Absolute difference |
| `SoftLight` | Subtle lighting |
| `HardLight` | Strong lighting |

## Drawing Primitives

```bash
# Draw a rectangle
magick input.png -fill none -stroke red -strokewidth 2 \
  -draw "rectangle 50,50 200,150" output.png

# Draw a circle
magick input.png -fill "rgba(255,0,0,0.5)" -stroke blue \
  -draw "circle 200,200 200,300" output.png

# Draw a line
magick input.png -stroke yellow -strokewidth 3 \
  -draw "line 0,0 400,300" output.png

# Draw a rounded rectangle
magick input.png -fill none -stroke white -strokewidth 2 \
  -draw "roundrectangle 50,50 250,200 15,15" output.png

# Draw a polygon
magick input.png -fill "rgba(0,255,0,0.3)" \
  -draw "polygon 100,10 40,198 190,78 10,78 160,198" output.png
```

## Creating Images from Scratch

```bash
magick -size 800x600 xc:white output.png               # Solid white
magick -size 800x600 xc:"#336699" output.png            # Solid hex color
magick -size 800x600 xc:transparent output.png          # Transparent (requires PNG/WebP)
magick -size 800x600 gradient:"red-blue" output.png     # Linear gradient
magick -size 800x600 radial-gradient:"white-black" out.png  # Radial gradient
magick -size 800x600 plasma: output.png                 # Plasma fractal
magick -size 800x600 xc: +noise Random output.png       # Random noise
magick -size 100x100 pattern:checkerboard output.png    # Built-in pattern
```

## Borders and Frames

```bash
magick input.png -bordercolor red -border 10 output.png          # Solid border
magick input.png -bordercolor "#333" -border 5x10 output.png     # Asymmetric border
magick input.png -mattecolor gray -frame 10x10+3+3 output.png    # 3D frame
magick input.png \( +clone -background black -shadow 60x5+5+5 \) \
  +swap -background white -layers merge +repage output.png       # Drop shadow
```

## Alpha / Transparency

```bash
magick input.png -alpha set -channel A -evaluate set 50% output.png  # Set 50% opacity
magick input.png -alpha off output.png                   # Remove alpha channel
magick input.png -alpha set -fuzz 20% -transparent white output.png  # Make white transparent
magick input.png -alpha extract mask.png                 # Extract alpha as grayscale
magick input.png mask.png -compose CopyOpacity -composite output.png  # Apply mask as alpha
magick input.png -background white -flatten output.jpg   # Flatten transparency to white
```

## Batch Processing with mogrify

**WARNING: `mogrify` modifies files in-place. Always work on copies or use `-path` to output elsewhere.**

```bash
# Resize all JPEGs in a directory
magick mogrify -resize 800x600 -path ./resized *.jpg

# Convert all PNGs to JPEG
magick mogrify -format jpg -path ./converted *.png

# Strip metadata from all images
magick mogrify -strip -path ./clean *.jpg

# Add watermark to all images
for f in *.jpg; do
  magick "$f" watermark.png -gravity southeast -composite "watermarked/$f"
done

# Resize + optimize for web
magick mogrify -resize "1200x1200>" -quality 80 -strip -path ./web *.jpg
```

## Montage (Contact Sheets / Grids)

```bash
# Simple grid of thumbnails
magick montage *.jpg -geometry 200x200+5+5 -tile 4x montage.jpg

# With labels
magick montage *.jpg -geometry 200x200+5+5 -tile 4x -label "%f" montage.jpg

# Custom background and border
magick montage *.jpg -geometry 150x150+10+10 -tile 3x \
  -background "#222" -bordercolor "#444" -border 2 montage.jpg
```

## Animated GIF Creation

```bash
# Create GIF from frames
magick -delay 10 -loop 0 frame_*.png animation.gif

# Optimize GIF
magick animation.gif -layers Optimize optimized.gif

# Resize GIF
magick animation.gif -resize 50% small.gif

# Change speed
magick input.gif -delay 5 faster.gif

# Add crossfade between images
magick -delay 100 img1.jpg -delay 10 \
  \( img1.jpg img2.jpg -morph 10 \) -delay 100 img2.jpg \
  -loop 0 crossfade.gif
```

## Image Comparison

```bash
magick compare image1.png image2.png diff.png            # Visual diff
magick compare -metric RMSE image1.png image2.png null: 2>&1  # Numeric diff (RMSE)
magick compare -metric AE -fuzz 5% img1.png img2.png null: 2>&1  # Absolute error with fuzz
```

### Comparison metrics

| Metric | Meaning |
|--------|---------|
| `AE` | Absolute error (pixel count) |
| `RMSE` | Root mean square error |
| `PSNR` | Peak signal-to-noise ratio |
| `SSIM` | Structural similarity |
| `MAE` | Mean absolute error |

## Image Sequences and Multi-Page

```bash
# Append images horizontally
magick img1.png img2.png img3.png +append wide.png

# Append images vertically
magick img1.png img2.png img3.png -append tall.png

# Stack with uniform size
magick img1.png img2.png -resize 400x300! +append output.png
```

## Performance Tips

- Use `-limit memory 1GiB -limit map 2GiB` for large images to prevent excessive memory use.
- Use `-thumbnail` instead of `-resize` when quality isn't critical (much faster).
- Pipe operations to avoid intermediate files: `magick input.png -resize 50% - | magick - -blur 0x3 output.png`
- Use `magick mogrify` for batch operations instead of shell loops.
- Add `-define jpeg:size=400x400` before reading JPEG to hint the decoder for faster loading when you only need a small result.

## Common Recipes

### Web-optimized thumbnail
```bash
magick input.jpg -thumbnail 300x300 -quality 80 -strip thumb.jpg
```

### Center-crop to exact aspect ratio
```bash
magick input.jpg -resize 1200x630^ -gravity center -extent 1200x630 og-image.jpg
```

### Add rounded corners
```bash
magick input.png \( +clone -alpha extract -draw "fill black polygon 0,0 0,15 15,0 fill white circle 15,15 15,0" \
  \( +clone -flip \) -compose Multiply -composite \
  \( +clone -flop \) -compose Multiply -composite \) \
  -alpha off -compose CopyOpacity -composite rounded.png
```

### Convert to ICO (favicon)
```bash
magick input.png -resize 32x32 -define icon:auto-resize=16,32,48 favicon.ico
```

### Create a sprite sheet
```bash
magick montage frame_*.png -geometry +0+0 -tile x1 -background none spritesheet.png
```
