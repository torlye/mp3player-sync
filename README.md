# mp3player-sync
Sync script to copy music library to an mp3 player, with conversion for unsupported files.

## The problem

Synchronizing a music library to an mp3 player (DAP, digital audio player) with limited file format support
can be a hassle. I want to keep the highest possible quality versions of songs in my music library, but
some of these files can't be played on my ageing Cowon mp3 player.

The Cowon J3 supports a variety of file formats, such as mp3, wma, ogg, m4a, and flac, so most files do not
require conversion. However, it crashes if it encounter 24-bit flac files, which are increasingly being offered
by artists on Bandcamp. It is also unable to display some embedded album covers.

## The solution

This configurable script will copy an entire media library folder to any destination path, which can be a mounted
memory card or the mp3 player's internal memory. It skips non-music files such as zip files and images.
It converts audio files and album convers as configured; in order to allow problem-free playback on the mp3 player.

The script can be re-run to sync new files (but it will not remove existing files). The script does not modify 
anything in the source folder.

My configuration for syncing with the Cowon J3 mp3 player:
* Files with sample rates higher than 48000 Hz are down-converted to 44100 Hz FLAC
* Files with bit depth higher than 16 bits are down-converted to 16-bit FLAC
* WAV files are converted to FLAC (this is just to save space on the player, it does support WAV files)
* Embedded cover art in formats other than JPEG are converted to JPEG. The Cowon does not support PNG/GIF cover art.
* Large cover art images are shrunk to a smaller size. The Cowon is slow to render very large images, 
so this speeds it up. It also saves some space.
* Extra embedded graphics are removed (some audio files contain multiple copies of the cover art). This saves space.
I have come across some mp3 files that have 10 MB of cover art for just 2 MB of audio data.
* If the source media files do not have cover art, but the source folder contains a cover.jpg file, this file
is embedded as cover art in the files in the destination folder.

## Implementation

Implemented as a cross-platform PowerShell script. Tested mainly on Windows and Ubuntu Linux.

### External tools
* PowerShell 7, to run the script
* FFmpeg, for transcoding audio files
* MediaInfo CLI, to analyze the source audio files
* Kid3 CLI, to read and write embedded cover art
* ImageMagick, to parse and convert the cover art

These tools are all available on Windows, Linux, and macOS, so in theory the script should work on those platforms.

To install all prerequisites on Ubuntu, run:
```
sudo apt install ffmpeg mediainfo kid3-cli imagemagick
sudo snap install powershell
```

When installing the prerequisites on Windows, make sure to get the CLI version of MediaInfo. 
Add the directory paths of each tool to the PATH environment variable.
The ImageMagick installer comes with FFmpeg bundled, and the installer can add the directory to PATH for you.

## Configuration
Source and destination paths are input arguments to the script. Other parameters are configurable by
editing the variables at the top of the script file:
* File extensions for audio files to include in sync
* File extensions for audio files that should be converted during sync
* Target format for audio transcoding
* Max sampling rate and bit depth supported by the player (files in higher quality will be down-converted)
* Embedded cover art image formats supported by the player (other formats will be converted)
* Max cover art image size, and target size for downsizing images
* Whether to skip files already synced, or to overwrite existing files
