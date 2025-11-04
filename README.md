# wdictation
Whisper Dictation. Capture audio, convert to text, paste into the current window.

Features
    • Speech to Text Dictation.
    
    • Record and preprocess audio.
    
    • Detect silence and stop recording automatically.
    
    • Dictated text is placed on clipboard.
    
    • Optionally paste the dictated text into the current window.

    

# Introduction
This project is comprised of the main script wdictation.sh and two Python cleanup scripts. The real work of course is done by whisper.cpp.
The flow looks like this:

Execute wdictation.sh. You might do this from a hotkey. You could also use the record button on my python toolbar application https://github.com/markd89/floatingtoolbar -- see toolbar_config.ini. For debug, of course, you’ll want to run it from the console.

There are several command-line parameters which can override the defaults in the beginning of the script, i.e. the number of seconds of silence to wait before we assume you’re done speaking.

The audio recording itself is done using sox. Sox was selected because it provides for silence detection to determine the end of the recording.

The recorded audio is stored in a temporary WAV file.

Whisper.cpp (faster and lighter than original Whisper) performs Speech-To-Text on the WAV file.
Cleanup scripts run on the converted text and fix a few annoying things. For example, when I say “going to”, Whisper.cpp would hear that as “gonna”. The script fixes that. When I’m speaking, I often chain thoughts together with And’s. Whisper.cpp wants to make these standalone sentences. The script removes the leading And and capitalizes the first character of the next work. So “And you’ll receive that soon.” becomes “You’ll receive that soon.”

The output text is placed on the keyboard and can be automatically pasted (into the current window) using xdotool.

As the script runs, you’ll see notifications of what it is doing from notify-send. 

My laptop has several audio inputs and I have had the best luck with the Plantronics headset. The script attempts to detect which device is the Plantronics and record from that. If it doesn’t find it, it fails back to the default microphone.  I had some challenges here and while it works well for me, I fully expect that someone (maybe you?) can improve the audio recording part. When I was testing, I would just run this line from the console with a WAV file and SILENCE_SEC hardcoded.
“sox -c 1 -r 16000 -b 16 -e signed-integer -L -t alsa default "$WAVFILE" silence 1 0.1 1% 1 "$SILENCE_SEC" 1%”

There’s quite a bit of debug and logging left in here. If this was really polished and rock solid, I’d want to pull that out. There are some other bits like multi-lingual that aren’t tested. Anyway, works for me and hope you find it useful.

# Dependencies
Whisper.cpp (https://github.com/ggml-org/whisper.cpp)

sox (Debian apt-get install sox)

arecord (Debian apt-get install alsa-utils)

xdotool (Debian apt-get install xdotool)


# Installation
1. Install dependencies.
2. Download the three scripts from this project and place them on your system (suggest /usr/local/bin). chmod +x wdictation.sh
3. Update wdictation.sh with the locations of the components on your system.
3. Test the wdictation.sh script from the console.
4. Once working, set it up to run from a hotkey.
The parameters that work well for me:
/usr/local/bin/wdictation.sh --no-notify --silence=2.0 --paste 
