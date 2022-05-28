param(
	[string]$inputPath,
	[string]$outputPath
)

# Copy all files with $audioFileExtensions file extensions to destination folder.
[string[]]$audioFileExtensions = ".mp3", ".flac", ".ogg", ".wav", ".m4a", ".wma"

# If audio file is one of $convertExtensions, convert it to $audioFormatForConversion
$audioFormatForConversion = "flac"
$audioFileExtensionForConversion = ".flac"
[string[]]$convertExtensions = ".wav"

# If audio bit depth is higher than $maxBitDepth, convert it to $targetBitDepth
$maxBitDepth = 16
$targetBitDepth = "s16" # ffmpeg sample_fmt

# If audio bit depth is higher than $maxSamplingRate, convert it to $targetSamplingRate
$maxSamplingRate = 48000
$targetSamplingRate = 44100

# If cover image is larger than $maxImageSize, resize to $idealImageSize
$idealImageSize = 272
$maxImageSize = 500

# If cover image is not one of the supported formats $supportedImageFormats, convert to $targetImageFormat
[string[]]$supportedImageFormats = "JPEG"
$targetImageFormat = ".jpg"

# Skip converting files that already exist in the destination folder
$skipExisting = $true

# Skip syncing these folders
$skipFolders = @("_New")

$tempFolder = [IO.Path]::GetTempPath()
$ErrorActionPreference = 'Stop'

function Convert-Folder([string]$currentInputFolder, [string]$currentOutputFolder) {
	if (Skip-Folder $currentInputFolder) {
		return
	}

	$folders = Get-ChildItem -Path $currentInputFolder -Directory
	$files = Get-ChildItem -Path $currentInputFolder -File | Where-Object {$_.Extension -in $audioFileExtensions}

	foreach ($file in $files)
	{
		Convert-File $file $currentOutputFolder
	}
	foreach ($folder in $folders)
	{
		$newSourceFolder = Join-Path $currentInputFolder $folder.Name
		$newTargetFolder = Join-Path $currentOutputFolder $folder.Name
		Convert-Folder $newSourceFolder $newTargetFolder
	}
}

function Get-MediaInfo([string]$filePath) {
	$info = mediainfo --Output=JSON $filePath
	$infoObj = $info | ConvertFrom-Json
	$track = $infoObj.media.track.Where({$_.'@type' -eq 'Audio'})[0]
	$general = $infoObj.media.track.Where({$_.'@type' -eq 'General'})[0]

	$bitDepth = $track.BitDepth
	if ($null -eq $bitDepth) { # mp3, m4a, ogg files do not report a bit depth. Assuming 16 bit.
		$bitDepth = 16
	}

	$hasCover = $null -ne $general.Cover -and $general.Cover.StartsWith('Yes')

	return $track.SamplingRate, $bitDepth, $hasCover
}

function Skip-File([System.IO.FileInfo]$file, [string]$destinationFolder) {
	$destinationPathFilter = Join-Path $destinationFolder $file.Name.Replace($file.Extension, '.*').Replace('[', '``[').Replace(']', '``]')
	return (Test-Path -Path $destinationPathFilter -PathType Leaf)
}

function Skip-Folder([string]$folderPath) {
	$item = Get-Item $folderPath
	return $skipFolders.Contains($item.Name)
}

function Convert-File([System.IO.FileInfo]$file, [string]$destinationFolder) {
	if ($skipExisting -and (Skip-File $file $destinationFolder)) {
		#Write-Host $file.Name "already converted. Skipping."
		return
	}

	$mediaInfo = Get-MediaInfo $file.FullName
	$samplingRate = $mediaInfo[0]
	$bitDepth = $mediaInfo[1]
	$hasCover = $mediaInfo[2]
	
	[string]$tempAudioFilePath = Convert-AudioFormat $file $samplingRate $bitDepth 
	
	Optimize-CoverImage $hasCover $file $tempAudioFilePath
	
	if ((Test-Path -PathType Container -Path $destinationFolder) -eq $false) {
		New-Item -ItemType Directory -Force -Path $destinationFolder
	}

	$tempAudioFile = Get-Item $tempAudioFilePath
	$destinationPath = (Join-Path $destinationFolder $file.Name).Replace($file.Extension, $tempAudioFile.Extension)
	Move-Item $tempAudioFilePath $destinationPath -Force
}

function Convert-AudioFormat([System.IO.FileInfo]$file, [int]$samplingRate, [int]$bitDepth) {
	$tempAudioFilePath = Get-TempFilePath
	if ($convertExtensions.Contains($file.Extension) -or $samplingRate -gt $maxSamplingRate -or $bitDepth -gt $maxBitDepth) {
		Write-Host $file.Name "requires conversion:" $bitDepth "bits" $samplingRate "Hz" $file.Extension

		$ffMpegArgs = @("-i", $file.FullName, "-f", $audioFormatForConversion, "-loglevel", "error")

		if ($bitDepth -gt $maxBitDepth) {
			$ffMpegArgs += "-sample_fmt"
			$ffMpegArgs += $targetBitDepth
		}
		if ($samplingRate -gt $maxSamplingRate) {
			$ffMpegArgs += "-ar"
			$ffMpegArgs += $targetSamplingRate
		}

		$tempAudioFilePath += $audioFileExtensionForConversion
		$ffMpegArgs += $tempAudioFilePath

		& 'ffmpeg' $ffMpegArgs
	}
	else {
		Write-Host $file.Name 'does not require conversion'
		$tempAudioFilePath += $file.Extension
		Copy-Item -LiteralPath $file.FullName -Destination $tempAudioFilePath
	}
	return $tempAudioFilePath
}

function Optimize-CoverImage([bool]$hasCover, [System.IO.FileInfo]$sourceFile, [string]$audioFilePath) {
	[string]$coverImgPath = $null
	if ($hasCover) {
		$coverImgPath = Export-CoverImage $audioFilePath
		Write-Host "Using embedded cover"
	}
	else {
		# check for cover.jpg
		$coverJpgPath = Join-Path $sourceFile.Directory.FullName "cover.jpg"
		
		if (Test-Path -Path $coverJpgPath -PathType Leaf) {
			$coverImgPath = $coverJpgPath
			Write-Host "Using cover.jpg from source folder"
		}
		else {
			Write-Error "No cover found for:" $sourceFile.FullName
			exit 1
		}
	}
	
	$convertedImgPath = Convert-CoverImage $coverImgPath
	Import-CoverImage $audioFilePath $convertedImgPath
	Remove-IfTempFile $convertedImgPath
	Remove-IfTempFile $coverImgPath
}

function Export-CoverImage([string]$audioFilePath) {
	$tempImgPath = Get-TempFilePath
	kid3-cli $audioFilePath -c "get picture:$(Convert-PathForKid3 $tempImgPath)" > $null
	if (-not(Test-Path -Path $tempImgPath -PathType Leaf)) {
		Write-Error "Cover image could not be extracted"
		exit 1
	}
	kid3-cli $audioFilePath -c "remove picture" > $null #Remove superfluous images (there can be more than one)
	#Write-Host "Exported from '$audioFilePath' to '$tempImgPath'"
	return $tempImgPath
}

function Import-CoverImage([string]$audioFilePath, [string]$coverImgPath) {
	kid3-cli $audioFilePath -c "set picture:$(Convert-PathForKid3 $coverImgPath) ''"
}

function Convert-CoverImage([string]$coverFileName) {
	[int]$width = magick identify -format "%w" $coverFileName
	$format = magick identify -format "%m" $coverFileName
	Write-Host "Cover is" $format "$($width)px"

	if ((-not $supportedImageFormats.Contains($format)) -or $width -gt $maxImageSize) {
		$convertedImgPath = Get-TempFilePath $targetImageFormat
		$targetImageSize = [System.Math]::Min($width, $idealImageSize)
		magick convert $coverFileName -resize "$($targetImageSize)x" -strip $convertedImgPath

		Write-Host "Cover converted to JPEG $($targetImageSize)px"
		return $convertedImgPath
	}
	else {
		Write-Host "Cover does not require conversion"
		return $coverFileName
	}
}

function Get-TempFilePath([string]$fileExtension) {
	return Join-Path $tempFolder "$([System.Guid]::NewGuid())$($fileExtension)"
}

function Remove-IfTempFile([string]$filePath) {
	if ($filePath.StartsWith($tempFolder) -and (Test-Path -PathType Leaf -Path $filePath)) {
		Remove-Item $filePath
	}
}

function Convert-PathForKid3([string]$path) {
	return $path.Replace("\", "\\").Replace("'", "\'")
}

Convert-Folder $inputPath $outputPath
