//
// INCLUDE FILES
//
#include <avr/interrupt.h>  
#include <avr/io.h>

////////////////////////////////////////////////////////////////////////////////
//
//
//
// LOW LEVEL USER INTERFACE FUNCTIONS
// - Drive the LEDs and read the switches
//
//
//
////////////////////////////////////////////////////////////////////////////////

// pin definitions
#define P_UI_HOLDSW      13
#define P_UI_IN_LED      12
#define P_UI_SYNCH_LED   11
#define P_UI_OUT_LED     10
#define P_UI_ENABLESW    9

#define P_UI_CLK     19  // PORTC.5
#define P_UI_DATA    18  // PORTC.4
#define P_UI_READ1   17  // PORTC.3
#define P_UI_READ0   16  // PORTC.2
#define P_UI_STROBE  15  // PORTC.1

#define BIT_UI_CLK     0b00100000
#define BIT_UI_DATA    0b00010000
#define BIT_UI_READ1   0b00001000
#define BIT_UI_READ0   0b00000100
#define BIT_UI_STROBE  0b00000010

#define NO_VALUE (-1)
#define DEBOUNCE_COUNT 50

#define LED_BRIGHT 255
#define LED_MEDIUM 16
#define LED_DIM 2
#define LED_OFF 0

#define UI_IN_LED_TIME     20
#define UI_OUT_LED_TIME    20
#define UI_SYNCH_LED_TIME  5

#define uiReadHoldSwitch() (digitalRead(P_UI_HOLDSW) == HIGH)
#define uiReadEnableSwitch() (digitalRead(P_UI_ENABLESW) == HIGH)

// The array of LED states
volatile byte uiLeds[16];

// Variables used for updating the display
volatile char uiDataKey;
volatile char uiLastDataKey;
volatile char uiMenuKey;
volatile char uiLastMenuKey;
volatile byte uiDebounce;
volatile byte uiScanPosition;
volatile byte uiLedOffPeriod;

unsigned long uiUnflashInLED;
unsigned long uiUnflashOutLED;
unsigned long uiUnflashSynchLED;

// Enumerate the menu keys
// Columns A, B, C 
// Rows 1,2,3,4
enum {
  UI_KEY_A1  = 3,
  UI_KEY_A2  = 2,
  UI_KEY_A3  = 1,
  UI_KEY_A4  = 0,

  UI_KEY_B1  = 4,
  UI_KEY_B2  = 5,
  UI_KEY_B3  = 6,
  UI_KEY_B4  = 7,

  UI_KEY_C1  = 11,
  UI_KEY_C2  = 10,
  UI_KEY_C3  = 9,
  UI_KEY_C4  = 8    
};

////////////////////////////////////////////////////////////////////////////////
//
// INTERRUPT SERVICE ROUTINE FOR UPDATING THE DISPLAY AND READING KEYBOARD
//
////////////////////////////////////////////////////////////////////////////////
ISR(TIMER2_OVF_vect) 
{
  // turn off LED strobe
  PORTC &= ~BIT_UI_STROBE;

  // Do we need to wait until turning the next LED on? (this is used implement
  // crude PWM brightness control)
  if(uiLedOffPeriod)
  {
    // ok, we need another interrupt before we illuminate the next LED
    TCNT2 = 255 - uiLedOffPeriod;
    uiLedOffPeriod = 0;
  }
  else
  {
    // need to start scanning from the start of the led row again?
    if(uiScanPosition >= 15)
    {
      // Clock a single bit into the shift registers
      PORTC &= ~BIT_UI_CLK;
      PORTC |= BIT_UI_DATA;
      PORTC |= BIT_UI_CLK;
    }

    // Shift the bit along (NB we need to shift it once 
    // before it will appear at shift reg output 0)
    PORTC &= ~BIT_UI_DATA;
    PORTC &= ~BIT_UI_CLK;
    PORTC |= BIT_UI_CLK;

    // does this LED need to be lit?    
    byte ledOnPeriod = uiLeds[uiScanPosition];
    if(ledOnPeriod)
    {
      // ok enable led strobe line
      PORTC |= BIT_UI_STROBE;      
    }     
    // set up the off period to make up a 255 clock tick cycle
    uiLedOffPeriod = 255 - ledOnPeriod;

    // check we're not debouncing the data entry keys
    if(!uiDebounce)
    {
      // is a data entry key pressed?
      if(!!(PINC & BIT_UI_READ0))
      {
        // is it a new keypress?
        if(uiLastDataKey != uiScanPosition)
        {
          // store it            
          uiDataKey = uiScanPosition;
          uiLastDataKey = uiDataKey;
          uiDebounce = DEBOUNCE_COUNT;
        }
      }
      // has the previously pressed key been released?
      else if(uiScanPosition == uiLastDataKey)
      {
        // no key is pressed
        uiLastDataKey = NO_VALUE;
      }
    }    
    else
    {
      // debouncing
      --uiDebounce;
    }

    // check for input at the menu keys
    // here we don't bother with a debounce
    if(!!(PINC & BIT_UI_READ1))
    {
      // is a new key pressed
      if(uiScanPosition != uiLastMenuKey)
      {
        // report it
        uiMenuKey = uiScanPosition;
        uiLastMenuKey = uiMenuKey;
      }
    }
    else if(uiScanPosition == uiLastMenuKey)
    {
      // previous key no longer pressed
      uiLastMenuKey = NO_VALUE;
    }



    if(!uiScanPosition)
      uiScanPosition = 15;
    else
      --uiScanPosition;


    TCNT2 = 255 - ledOnPeriod;
  }
}

////////////////////////////////////////////////////////////////////////////////
// UI INIT
void uiInit()
{
  pinMode(P_UI_CLK, OUTPUT);     
  pinMode(P_UI_DATA, OUTPUT);     
  pinMode(P_UI_READ1, INPUT);     
  pinMode(P_UI_READ0, INPUT);     
  pinMode(P_UI_STROBE, OUTPUT);     

  pinMode(P_UI_HOLDSW, INPUT);
  pinMode(P_UI_IN_LED, OUTPUT);
  pinMode(P_UI_OUT_LED, OUTPUT);
  pinMode(P_UI_SYNCH_LED, OUTPUT);
  pinMode(P_UI_ENABLESW, INPUT);

  // enable pullups
  digitalWrite(P_UI_HOLDSW, HIGH);
  digitalWrite(P_UI_ENABLESW, HIGH);

  for(int i=0;i<16;++i)
    uiLeds[i] = LED_OFF;  

  uiDataKey = NO_VALUE;
  uiLastDataKey = NO_VALUE;
  uiMenuKey = NO_VALUE;
  uiDebounce = 0;
  uiScanPosition = 15;
  uiLedOffPeriod = 0;
  uiUnflashInLED = 0;
  uiUnflashOutLED = 0;
  uiUnflashSynchLED = 0;

  // start the interrupt to service the UI   
  TCCR2A = 0;
  TCCR2B = 1<<CS21 | 1<<CS20;
  TIMSK2 = 1<<TOIE2;
  TCNT2 = 0; 
}

////////////////////////////////////////////////////////////////////////////////
// FLASH IN LED
void uiFlashInLED(unsigned long milliseconds)
{
  digitalWrite(P_UI_IN_LED, HIGH);
  uiUnflashInLED = milliseconds + UI_IN_LED_TIME;
}

////////////////////////////////////////////////////////////////////////////////
// FLASH OUT LED
void uiFlashOutLED(unsigned long milliseconds)
{
  digitalWrite(P_UI_OUT_LED, HIGH);
  uiUnflashOutLED = milliseconds + UI_OUT_LED_TIME;
}

////////////////////////////////////////////////////////////////////////////////
// FLASH SYNCH LED
void uiFlashSynchLED(unsigned long milliseconds)
{
  digitalWrite(P_UI_SYNCH_LED, HIGH);
  uiUnflashSynchLED = milliseconds + UI_SYNCH_LED_TIME;
}

////////////////////////////////////////////////////////////////////////////////
//  CLEAR ALL LEDS
void uiClearLeds()
{
  for(int i=0;i<16;++i)
    uiLeds[i] = 0;
}

////////////////////////////////////////////////////////////////////////////////
// SET A RANGE OF LEDS TO SAME STATUS
void uiSetLeds(int start, int len, byte newStatus)
{
  while(start < 16 && len-- > 0)
    uiLeds[start++] = newStatus;
}

////////////////////////////////////////////////////////////////////////////////
// RUN THE UI STATE MACHINE
void uiRun(unsigned long milliseconds)
{
  if(uiUnflashInLED && uiUnflashInLED < milliseconds)
  {
    digitalWrite(P_UI_IN_LED, LOW);
    uiUnflashInLED = 0;
  }
  if(uiUnflashOutLED && uiUnflashOutLED < milliseconds)
  {
    digitalWrite(P_UI_OUT_LED, LOW);
    uiUnflashOutLED = 0;
  }
  if(uiUnflashSynchLED && uiUnflashSynchLED < milliseconds)
  {
    digitalWrite(P_UI_SYNCH_LED, LOW);
    uiUnflashSynchLED = 0;
  }
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
//
//
//
// LOW LEVEL MIDI HANDLING
//
//
//
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

// max ms we will wait for a mandatory midi parameter to arrive
#define MIDI_PARAM_TIMEOUT  50

// state variables
byte midiInRunningStatus;
byte midiOutRunningStatus;
byte midiNumParams;
byte midiParams[2];
byte midiSendChannel;

// macros
#define MIDI_IS_NOTE_ON(msg) ((msg & 0xf0) == 0x90)
#define MIDI_IS_NOTE_OFF(msg) ((msg & 0xf0) == 0x80)
#define MIDI_MK_NOTE_ON (0x90 | midiSendChannel)
#define MIDI_MK_NOTE_OFF (0x80 | midiSendChannel)

// realtime synch messages
#define MIDI_SYNCH_TICK     0xf8
#define MIDI_SYNCH_START    0xfa
#define MIDI_SYNCH_CONTINUE 0xfb
#define MIDI_SYNCH_STOP     0xfc


////////////////////////////////////////////////////////////////////////////////
// MIDI INIT
void midiInit()
{
  // init the serial port
  Serial.begin(31250);
  Serial.flush();

  midiInRunningStatus = 0;
  midiOutRunningStatus = 0;
  midiNumParams = 0;
  midiSendChannel = 0;
}

////////////////////////////////////////////////////////////////////////////////
// MIDI WRITE
void midiWrite(byte statusByte, byte param1, byte param2, byte numParams, unsigned long milliseconds)
{
// TODO: sysex passthru should set running status?
  if((statusByte & 0xf0) == 0xf0)
  {
    // realtime byte pass straight through
    Serial.write(statusByte);
  }
  else
  {
    // send channel message
    if(midiOutRunningStatus != statusByte)
    {
      Serial.write(statusByte);
      midiOutRunningStatus = statusByte;
    }
    if(numParams > 0)
      Serial.write(param1);
    if(numParams > 1)
      Serial.write(param2);    
  }
  
  // indicate activity
  uiFlashOutLED(milliseconds);
}

////////////////////////////////////////////////////////////////////////////////
// MIDI READ / THRU
byte midiRead(unsigned long milliseconds, byte passThru)
{
  // is anything available?
  if(Serial.available())
  {
    // read next character
    byte ch = Serial.read();
    byte doThru = 0;

    // Is it a status byte
    if((ch & 0x80)>0)
    {
      // Interpret the status byte
      switch(ch & 0xf0)
      {
      case 0x80: //  Note-off  2  key  velocity  
      case 0x90: //  Note-on  2  key  veolcity  
      case 0xA0: //  Aftertouch  2  key  touch  
        midiInRunningStatus = ch;
        midiNumParams = 2;
        doThru = passThru;
        break;

      case 0xB0: //  Continuous controller  2  controller #  controller value  
      case 0xC0: //  Patch change  2  instrument #   
      case 0xE0: //  Pitch bend  2  lsb (7 bits)  msb (7 bits)  
        midiInRunningStatus = ch;
        midiNumParams = 2;
        doThru = 1;
        break;

      case 0xD0: //  Channel Pressure  1  pressure  
        midiInRunningStatus = ch;
        midiNumParams = 1;
        doThru = passThru;
        break;

      case 0xF0: //  Realtime etc, no params
        return ch; 
      }
    }

    // do we have an active message
    if(midiInRunningStatus)
    {
      // read params for the message
      for(int thisParam = 0; thisParam < midiNumParams; ++thisParam)
      {
        // they might not have arrived yet!
        if(!Serial.available())
        {
          // if the next param is not ready then we need to wait
          // for it... but not forever (we don't want to hang)
          unsigned long midiTimeout = millis() + MIDI_PARAM_TIMEOUT;
          while(!Serial.available())
          {
            if(millis() > midiTimeout)
              return 0;
          }
        }
        midiParams[thisParam] = Serial.read();
      }

      // echo to output if needed
      if(doThru)
        midiWrite(midiInRunningStatus, midiParams[0], midiParams[1], midiNumParams, milliseconds);

      // flash the LED
      uiFlashInLED(milliseconds);

      // return the status byte (caller will read params from global variables)
      return midiInRunningStatus;
    }
  }

  // nothing pending
  return 0;
}

////////////////////////////////////////////////////////////////////////////////
// MIDI SEND REALTIME
void midiSendRealTime(byte msg)
{
  Serial.write(msg);
}


////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
//
//
//
// SYNCHRONISATION
// - Functions for managing the beat clock
//
//
//
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

// variables
byte synchToMIDI;                     // whether we're synching to MIDI
byte synchSendMIDI;                   // whether the MIDI clock is to be sent
unsigned long synchTickCount;         // tick count
int synchPlayRate;                    // ratio of ticks per arp note
unsigned long synchPlayIndex;         // arp note count
byte synchPlayAdvance;                // flag to indicate that next arp note can be played
byte synchRestartPlay;                // restart play index flag
int synchBPM;                         // internal synch bpm
int synchInternalTickPeriod;          // internal synch millseconds per tick
unsigned long synchNextInternalTick;  // internal synch next tick time

byte synchBeat;                       // flag for flashing the SYNCH lamp
byte synchSendEvent;                  // synch events to send

// PIN DEFS (From PIC MCU servicing MIDI SYNCH input)
#define P_SYNCH_TICK     2
#define P_SYNCH_RESTART  3
#define P_SYNCH_RUN      4

#define MILLISECONDS_PER_MINUTE 60000
#define TICKS_PER_QUARTER_NOTE 24
#define SYNCH_DEFAULT_BPM 120

#define SYNCH_SEND_TICK  0x01
#define SYNCH_SEND_START 0x02
#define SYNCH_SEND_STOP  0x04

// Values for synchRate
enum
{
  SYNCH_RATE_1   = 96,
  SYNCH_RATE_2D  = 72,
  SYNCH_RATE_2   = 48,
  SYNCH_RATE_4D  = 36,
  SYNCH_RATE_4   = 24,
  SYNCH_RATE_8D  = 18,
  SYNCH_RATE_2T  = 16,
  SYNCH_RATE_8   = 12,
  SYNCH_RATE_4T  = 8,
  SYNCH_RATE_8T  = 4,
  SYNCH_RATE_16D = 9,
  SYNCH_RATE_16  = 6,
  SYNCH_RATE_32  = 3,
  SYNCH_RATE_16T = 2
};

//////////////////////////////////////////////////////////////////////////
// SYNCH TICK
void synchTick()
{
  ++synchTickCount;
  if(!(synchTickCount % synchPlayRate))
  {
    if(synchRestartPlay)
    {
      synchPlayIndex = 0;
      synchRestartPlay = 0;
    }
    else 
    {
      synchPlayIndex++;
    }
    synchPlayAdvance = 1;
  }
  if(!(synchTickCount % TICKS_PER_QUARTER_NOTE))
    synchBeat = 1;  
    
  if(synchSendMIDI)
  {
    synchSendEvent |= SYNCH_SEND_TICK;
  }
}

//////////////////////////////////////////////////////////////////////////
// SYNCH RESTART
void synchRestart()
{
  synchTickCount = 0;
  synchPlayIndex = 0;
  synchPlayAdvance = 1;
  synchRestartPlay = 0;
  synchBeat = 1;  
}

//////////////////////////////////////////////////////////////////////////
//
// synchReset_ISR
// Called at start of bar
// 
//////////////////////////////////////////////////////////////////////////
ISR(synchReset_ISR)
{
  synchRestart();
}

//////////////////////////////////////////////////////////////////////////
//
// synchTick_ISR
// Called on midi synch
// 
//////////////////////////////////////////////////////////////////////////
ISR(synchTick_ISR)
{
  synchTick();
}

//////////////////////////////////////////////////////////////////////////
// SET TEMPO
void synchSetTempo(int bpm)
{
  synchBPM = bpm;
  synchInternalTickPeriod = (float)MILLISECONDS_PER_MINUTE/(bpm * TICKS_PER_QUARTER_NOTE);
}

////////////////////////////////////////////////////////////////////////////////
// SYNCH INIT
void synchInit()
{
  // by default don't synch
  synchToMIDI = 0; 
  
  // by default do not send synch
  synchSendMIDI = 0;

  // set default play rate
  synchPlayRate = SYNCH_RATE_16;
  
  // reset the counters
  synchRestart();

  // initialise internal synch generator
  synchSetTempo(SYNCH_DEFAULT_BPM);
  synchNextInternalTick = 0;

  pinMode(P_SYNCH_TICK, INPUT);
  pinMode(P_SYNCH_RESTART, INPUT);
  pinMode(P_SYNCH_RUN, INPUT);

  // weak pull-ups
  digitalWrite(P_SYNCH_TICK, HIGH);
  digitalWrite(P_SYNCH_RESTART, HIGH);
  digitalWrite(P_SYNCH_RUN, HIGH);

  attachInterrupt(0, synchReset_ISR, RISING);
  attachInterrupt(1, synchTick_ISR, RISING);
  interrupts();
}

////////////////////////////////////////////////////////////////////////////////
// SYNCH RUN
void synchRun(unsigned long milliseconds)
{
  // are we synching to MIDI?
  if(!synchToMIDI)
  {      
    // need to generate our own ticks
    if(synchNextInternalTick < milliseconds)
    {
      synchTick();
      synchNextInternalTick = milliseconds + synchInternalTickPeriod;
    }
  }

  // stop?
  if(synchSendEvent & SYNCH_SEND_STOP)
  {
    midiSendRealTime(MIDI_SYNCH_STOP);
  }
  else
  {
    // start?
    if(synchSendEvent & SYNCH_SEND_START)
      midiSendRealTime(MIDI_SYNCH_START);
      
    // tick?
    if(synchSendEvent & SYNCH_SEND_TICK)
      midiSendRealTime(MIDI_SYNCH_TICK);
  }
  synchSendEvent = 0;

  // check if we need to report a beat
  if(synchBeat)
  {
    uiFlashSynchLED(milliseconds);
    synchBeat = 0;
  } 
}


////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
//
//
//
//
// ARPEGGIATOR FUNCTIONS
//
//
//
//
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

// Macro defs
#define ARP_MAX_CHORD 12
#define ARP_MAKE_NOTE(note, vel) (((vel)<<8)|(note))
#define ARP_GET_NOTE(x) ((x)&0x7f)
#define ARP_GET_VELOCITY(x) (((x)>>8)&0x7f)
#define ARP_MAX_SEQUENCE 100

// Values for arpType
enum 
{
  ARP_TYPE_UP = 0,
  ARP_TYPE_DOWN,
  ARP_TYPE_UP_DOWN,
  ARP_TYPE_RANDOM,
  ARP_TYPE_MANUAL
};

// Values for arpInsertMode
enum
{
  ARP_INSERT_OFF = 0,
  ARP_INSERT_HI,
  ARP_INSERT_LOW,
  ARP_INSERT_3_1,
  ARP_INSERT_4_2
};

// ARP PARAMETERS
byte arpType;              // arpeggio type
char arpOctaveShift;       // octave transpose
byte arpOctaveSpan;        // number of octaves to span with the arpeggio
byte arpInsertMode;        // additional note insertion mode
byte arpVelocity;          // velocity (0 = manual)
byte arpGateLength;        // gate length (0 = tie notes)
char arpTranspose;         // up/down transpose

// CHORD INFO - notes held by user
int arpChord[ARP_MAX_CHORD];
int arpChordLength;        // number of notes in the chord
int arpNotesHeld;          // number of notes physically held

// ARPEGGIO SEQUENCE - the arpeggio build from chord/inserts etc
byte arpSequence[ARP_MAX_SEQUENCE];
int arpSequenceLength;     // number of notes in the sequence

// NOTE PATTERN - the rythmic pattern of played/muted notes
byte arpPattern[ARP_MAX_SEQUENCE];
byte arpPatternLength;   // user-defined pattern length (1-16)
byte arpPatternIndex;    // position in the pattern (for display)

byte arpRefresh;  // whether the pattern index is changed

// STOP NOTE - remembers which (single) note is playing
// and when it should be stopped
byte arpStopNote;
unsigned long arpStopNoteTime;

// used to time the length of a step
unsigned long arpLastPlayAdvance;

// ARP STATUS FLAGS
byte arpRebuild;          // whether the sequence needs to be rebuilt

////////////////////////////////////////////////////////////////////////////////
// ARP INIT
void arpInit()
{
//  arpHold = 0;
  arpType = ARP_TYPE_UP;
  arpOctaveShift = 0;
  arpOctaveSpan = 1;
  arpInsertMode = ARP_INSERT_OFF;
  arpVelocity = 127; //TODO - default manual
  arpChordLength = 0;
  arpNotesHeld = 0;
  arpPatternLength = 16;
  arpRefresh = 0;
  arpRebuild = 0;
  arpStopNote = 0;
  arpGateLength = 10;
  arpSequenceLength = 0;
  arpLastPlayAdvance = 0;
  arpTranspose = 0;

  
  // the pattern starts with all beats on
  for(int i=0;i<16;++i)
    arpPattern[i] = 1;
}

////////////////////////////////////////////////////////////////////////////////
// COPY CHORD
void arpCopyChord(int *dest)
{
  int i;
  for(i=0; i<arpChordLength; ++i)
    dest[i] = arpChord[i];
}

////////////////////////////////////////////////////////////////////////////////
// SORT NOTES OF CHORD
// Crappy bubblesort.. but there are not too many notes
void arpSortChord(int *dest)
{
  arpCopyChord(dest);
  byte sorted = 0;
  while(!sorted)
  {
    sorted = 1;
    for(int i=0; i<arpChordLength-1; ++i)
    {
       if(ARP_GET_NOTE(dest[i]) > ARP_GET_NOTE(dest[i+1]))
       {
         int t = dest[i];
         dest[i] = dest[i+1];
         dest[i+1] = t;
         sorted = 0;
       }
    }
  }
}

////////////////////////////////////////////////////////////////////////////////
// RANDOMIZE CHORD
void arpRandomizeChord(int *dest)
{
  int i,j;
  
  // clear destination buffer
  for(i=0; i<arpChordLength; ++i)
    dest[i] = 0;
    
  // loop through the source chord
  for(i=0; i<arpChordLength; ++i)
  {
    // loop until we find a place to 
    // put this note in dest buffer
    for(;;)
    {
       // look for a place
       j = random(arpChordLength);
       if(!dest[j])
       {
          // its empty, so we can use it
          dest[j] = arpChord[i];
          break;
       }
    }        
  }
}

  
////////////////////////////////////////////////////////////////////////////////
// BUILD A NEW SEQUENCE
void arpBuildSequence()
{
  // sequence is empty if no chord notes present
  arpSequenceLength=0;
  if(!arpChordLength)
    return;
    
  // sort the chord info if needed
  int chord[ARP_MAX_CHORD];
  if(arpType == ARP_TYPE_UP || arpType == ARP_TYPE_DOWN || arpType == ARP_TYPE_UP_DOWN)
    arpSortChord(chord);
  else
    arpCopyChord(chord);

  int tempSequence[ARP_MAX_SEQUENCE];
  int tempSequenceLength = 0;        
  int highestNote = ARP_MAKE_NOTE(0,0);
  int lowestNote = ARP_MAKE_NOTE(127,0);    

  // This outer loop allows us two passes for UP-DOWN mode
  int nextPass = 1;    
  while(nextPass && 
        tempSequenceLength < ARP_MAX_SEQUENCE)
  {
    // this loop is for the octave span
    int octaveCount;
    for(octaveCount = 0; 
      octaveCount < arpOctaveSpan && tempSequenceLength < ARP_MAX_SEQUENCE; 
      ++octaveCount)
    {
      // Set up depending on arp type
      int transpose;
      int chordIndex;
      int lastChordIndex;
      int chordIndexDelta;      
      switch(arpType)
      {
        case ARP_TYPE_RANDOM:
          arpRandomizeChord(chord);
          // fall thru
        case ARP_TYPE_UP:
        case ARP_TYPE_MANUAL:
          chordIndex = 0;
          lastChordIndex = arpChordLength - 1;
          transpose = arpTranspose + 12 * (arpOctaveShift + octaveCount);    
          chordIndexDelta = 1;
          nextPass = 0;
          break;          
        
        case ARP_TYPE_DOWN:
          chordIndex = arpChordLength - 1;;
          lastChordIndex = 0;
          transpose = arpTranspose + 12 * (arpOctaveShift + arpOctaveSpan - octaveCount - 1);    
          chordIndexDelta = -1;
          nextPass = 0;
          break;          

        case ARP_TYPE_UP_DOWN:        
          if(nextPass == 1)
          {
            // going up we can play all the notes
            chordIndex = 0;
            lastChordIndex = arpChordLength - 1;
            chordIndexDelta = 1;
            transpose = arpTranspose + 12 * (arpOctaveShift + octaveCount);    
            if(octaveCount == arpOctaveSpan - 1)
              nextPass = 2;
          }
          else
          {
            // GOING DOWN!
            // Is the range just one octave?
            if(arpOctaveSpan == 1)
            {
              // On the way down we don't play top or bottom notes of the chord
              chordIndex = arpChordLength - 2;
              lastChordIndex = 1;
              nextPass = 0;
            }
            // are we on the top octave of the descent?
            else if(octaveCount == 0)
            {
              // the top note is skipped, the bottom note can be played
              chordIndex = arpChordLength - 2;
              lastChordIndex = 0;
            }
            // are we on the bottom octave of the descent?
            else if(octaveCount == arpOctaveSpan - 1)
            {
              // top note can be played but bottom note is not
              chordIndex = arpChordLength - 1;
              lastChordIndex = 1;
              
              // this the the last octave to play
              nextPass = 0;
            }
            else
            {
              // this is not first or last octave of the descent, so there
              // is no need to skip any of the notes
              chordIndex = arpChordLength - 1;
              lastChordIndex = 0;
            }
            transpose = arpTranspose + 12 * (arpOctaveShift + arpOctaveSpan - octaveCount - 1);    
            chordIndexDelta = -1;
          }
          break;
      }        

      // Write notes from the chord into the arpeggio sequence
      while(chordIndex >= 0 && 
            chordIndex < arpChordLength && 
            tempSequenceLength < ARP_MAX_SEQUENCE)
      {
        // fetch the current note
        int note = ARP_GET_NOTE(chord[chordIndex]);
        byte velocity = ARP_GET_VELOCITY(chord[chordIndex]);
        
        // transpose as needed
        note += transpose;
        while(note>127)
          note -= 12;
        while(note<0)
          note += 12;          
        int newNote = ARP_MAKE_NOTE(note, velocity);
        
        // track lowest and highest notes
        if(note > ARP_GET_NOTE(highestNote))
          highestNote = newNote;
        if(note < ARP_GET_NOTE(lowestNote))
          lowestNote = newNote;
          
        // insert into sequence
        tempSequence[tempSequenceLength++] = newNote;
        
        // have we reached the last note we want?
        if(chordIndex == lastChordIndex)
          break;
          
        // skip to next note in the chord
        chordIndex += chordIndexDelta;
      }      
    }           
  }  
  
    
  // we have the expanded sequence for one octave... now we need to 
  // perform any necessary note insertions
  int i, j;
  arpSequenceLength = 0;
  switch(arpInsertMode)
  {
    case ARP_INSERT_OFF:
      for(i=0; i<tempSequenceLength; ++i)
        arpSequence[arpSequenceLength++] = tempSequence[i];
      break;
    case ARP_INSERT_HI:
      for(i=0; i<tempSequenceLength && arpSequenceLength < ARP_MAX_SEQUENCE; ++i)
      {
        if(tempSequence[i] != highestNote)
        {
          arpSequence[arpSequenceLength++] = highestNote;
          arpSequence[arpSequenceLength++] = tempSequence[i];
        }
      }
      break;
    case ARP_INSERT_LOW:
      for(i=0; i<tempSequenceLength && arpSequenceLength < ARP_MAX_SEQUENCE; ++i)
      {
        if(tempSequence[i] != lowestNote)
        {
          arpSequence[arpSequenceLength++] = lowestNote;
          arpSequence[arpSequenceLength++] = tempSequence[i];
        }
      }
      break;
    case ARP_INSERT_3_1: // 3 steps forward and one back 012123234345456
      i = 0;
      j = 0;
      while(i<tempSequenceLength && arpSequenceLength < ARP_MAX_SEQUENCE)
      {
        arpSequence[arpSequenceLength++] = tempSequence[i];
        if(!(++j%3))
          i--;
        else
          i++;
      }
      break;
    case ARP_INSERT_4_2: // 4 steps forward and 2 back 0123123423453456
      i = 0;
      j = 0;
      while(i<tempSequenceLength && arpSequenceLength < ARP_MAX_SEQUENCE)
      {
        arpSequence[arpSequenceLength++] = tempSequence[i];
        if(!(++j%4))
          i-=2;
        else
          i++;
      }
      break;
  }
}  



////////////////////////////////////////////////////////////////////////////////
// 
// READ THE MIDI INPUT AND UPDATE THE CHORD BUFFER
// 
////////////////////////////////////////////////////////////////////////////////
void arpReadInput(unsigned long milliseconds)
{
  int i;

  // read HOLD mode
  byte hold = uiReadHoldSwitch();
    
  // we may have multiple notes to read
  for(;;)
  {
    // read the MIDI port
    byte msg = midiRead(milliseconds, 0);      
    if(!msg)
      break;
    byte note = midiParams[0];
    byte velocity = midiParams[1];
      
    // NOTE ON?
    if(MIDI_IS_NOTE_ON(msg) && velocity && note)
    {
      // If we in hold mode and has the user released all
      // notes of the previous chord, then a new chord is
      // started with the first new note
      if(hold && !arpNotesHeld)
        arpChordLength = 0;

      // first note of a chord restarts the arpeggiator
      // sequence from the first beat
      if(!arpChordLength)
        synchRestartPlay = 1;
        
      // room for another note?
      if(arpChordLength < ARP_MAX_CHORD-1)
      {        
        // ensure we don't somehow end up with duplicate
        // notes in the chord (should not happen, since
        // we should get a note off before another note
        // on... but just in case)
        for(i=0;i<arpChordLength;++i)
        {
          if(ARP_GET_NOTE(arpChord[i])== note)
            break;
        }
        if(i == arpChordLength)
        {
          // insert the new note into the chord                   
          arpChord[arpChordLength] = ARP_MAKE_NOTE(note,velocity);
          arpChordLength++;
          
          // flag that the arp sequence needs to be rebuilt
          arpRebuild = 1;
        }
      }
  
      // track the number of notes held by the user
      ++arpNotesHeld;  
    }
    // user releases a note (NB might be note on with zero velocity)
    else if(MIDI_IS_NOTE_ON(msg) || MIDI_IS_NOTE_OFF(msg))
    {
      // one less note that is still held
      --arpNotesHeld;
 
      // should the note be removed from the chord?
      if(!hold)
      {     
        // search for the note in the chord
        for(i=0; i<arpChordLength; ++i)
        {
          // did we find the released key in the chord?
          if(ARP_GET_NOTE(arpChord[i]) == note)
            break;
        }
        
        // shift higher notes down one position
        // to remove the released note
        for(; i < arpChordLength-1; ++i)
          arpChord[i] = arpChord[i+1];
    
        // rebuild the sequence
        --arpChordLength;
        arpRebuild = 1;
      }
    }
  }
   
  // check if the hold switch is released while
  // there are notes being held
  if(!hold && !arpNotesHeld && arpChordLength)
  {
    arpChordLength = 0;
    arpRebuild = 1;
  }
}

////////////////////////////////////////////////////////////////////////////////
//
// ARP RUN
// Run the arpeggiator state machine
// 
////////////////////////////////////////////////////////////////////////////////
void arpRun(unsigned long milliseconds)
{  
  // if the arpeggiator is enabled
  if(uiReadEnableSwitch())
  {
    // update the chord based on user input
    arpReadInput(milliseconds);
  }
  else
  {
    // just pass through channel messages
    midiRead(milliseconds, 1);
  }

  // see if user has changed a setting that would mean the
  // sequence needs to be rebuilt
  if(arpRebuild)
  {
    // rebuild the sequence 
    arpBuildSequence();                
    arpRebuild = 0;
  }

  // have we updated the play position?
  if(synchPlayAdvance && arpSequenceLength && arpPatternLength)
  {           
    // get the index into the arpeggio sequence
    int sequenceIndex = synchPlayIndex % arpSequenceLength;

    // and the index into the pattern
    arpPatternIndex = synchPlayIndex % arpPatternLength;

    // check if we should be sending notes
    if(uiReadEnableSwitch())
    {            
      // check there is a note not a rest at this 
      // point in the pattern
      if(arpPattern[arpPatternIndex])
      {
        byte note = ARP_GET_NOTE(arpSequence[sequenceIndex]);
        byte velocity = (!arpVelocity)? ARP_GET_VELOCITY(arpSequence[sequenceIndex]) : arpVelocity;        

        // start the note playing
        if(note > 0)
          midiWrite(MIDI_MK_NOTE_ON, note, velocity, 2, milliseconds);

        // if the previous note is still playing then stop it
        // (should be the case only for "tie" mode)
        if(arpStopNote && arpStopNote != note)
        {
          midiWrite(MIDI_MK_NOTE_OFF, arpStopNote, 0, 2, milliseconds);
        }

        // need to work out the gate length for this note
        arpStopNote = note;
        if(arpGateLength)
        {              
          // determined by user entered gate length
          unsigned long stepLength = milliseconds - arpLastPlayAdvance;
          arpStopNoteTime = milliseconds + (stepLength * arpGateLength) / 16;
        }
        else
        {
          // note till play till the next one starts
          arpStopNoteTime = 0;               
        }
        arpLastPlayAdvance = milliseconds;
      }
    }    

    // need to update the arp display
    arpRefresh = 1;
    synchPlayAdvance = 0;
  }
  // check if a note needs to be stopped.. either at end of playing or if there is no sequence
  // and we're in tied note mode
  else if(arpStopNote && (
    ((arpStopNoteTime && arpStopNoteTime < milliseconds) || 
    (!arpStopNoteTime && !arpSequenceLength))))
  {
    // stop the ringing note
    midiWrite(MIDI_MK_NOTE_OFF, arpStopNote, 0, 2, milliseconds);
    arpStopNote = 0;
    arpStopNoteTime = 0;
  }
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
//
//
//
//
// CONTROL SURFACE
//
//
//
//
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////


// map the edit keys to physical buttons
//
// PATN  LEN   MODE
// SHFT  SPAN  RATE
// VELO  GATE  INS
// TMPO  CHAN  TRAN
enum {
  EDIT_MODE_PATTERN          = UI_KEY_A1,
  EDIT_MODE_PATTERN_LENGTH   = UI_KEY_B1,
  EDIT_MODE_ARP_TYPE         = UI_KEY_C1,
  EDIT_MODE_OCTAVE_SHIFT     = UI_KEY_A2,
  EDIT_MODE_OCTAVE_SPAN      = UI_KEY_B2,
  EDIT_MODE_RATE             = UI_KEY_C2,
  EDIT_MODE_VELOCITY         = UI_KEY_A3,
  EDIT_MODE_GATE_LENGTH      = UI_KEY_B3,
  EDIT_MODE_INSERT           = UI_KEY_C3,
  EDIT_MODE_TEMPO_SYNCH      = UI_KEY_A4,
  EDIT_MODE_CHANNEL          = UI_KEY_B4,
  EDIT_MODE_TRANSPOSE        = UI_KEY_C4
};

// Time in ms when we go back to pattern
// edit mode after last button press
#define EDIT_REVERT_TIME 10000

// current editing mode
byte editMode;

// track the revert time
unsigned long editRevertTime;

////////////////////////////////////////////////////////////////////////////////
// INIT EDITING
void editInit()
{
  editMode = EDIT_MODE_PATTERN;
  editRevertTime = 0;
}

////////////////////////////////////////////////////////////////////////////////
// EDIT PATTERN
void editPattern(byte keyPress, byte forceRefresh)
{
  if(keyPress != NO_VALUE)
  {
    arpPattern[keyPress] = !arpPattern[keyPress];
    forceRefresh = 1;
  }

  if(forceRefresh || arpRefresh)
  {
//    int i= arpChordLength;
//    uiClearLeds();
//    uiSetLeds(0, i, LED_MEDIUM);
//    if(i<0) uiSetLeds(0, 15, LED_BRIGHT);
    
    // copy the leds
    for(int i=0; i<16; ++i)
      uiLeds[i] = arpPattern[i] ? LED_MEDIUM : LED_OFF;
      
    // only display the play position if we have a sequence
    if(arpSequenceLength)    
      uiLeds[arpPatternIndex] = LED_BRIGHT;

    // reset the flag
    arpRefresh = 0;
  }
}

/////////////////////////////////////////////////////
// EDIT PATTERN LENGTH
void editPatternLength(byte keyPress, byte forceRefresh)
{
  int i;
  if(keyPress >= 0 && keyPress <= 15)
  {
    arpPatternLength = keyPress + 1;
    forceRefresh = 1;
  }

  if(forceRefresh)
  {    
    uiClearLeds();
    uiSetLeds(0, arpPatternLength, LED_DIM);
    uiLeds[arpPatternLength-1] = LED_BRIGHT;
  }
}

/////////////////////////////////////////////////////
// EDIT ARPEGGIO TYPE
void editArpType(byte keyPress, byte forceRefresh)
{
  int i;
  switch(keyPress)
  {
    case 0: case 1:  case 2:  case 3: case 4:
      arpType = keyPress;
      arpRebuild = 1;
      forceRefresh = 1;
      break;
    case 13: 
      arpPatternLength = 8+random(8);
      for(i = 0;i<16;++i) arpPattern[i] = random(2);
      break;
    case 14:
      for(i = 0;i<16;++i) arpPattern[i] = 0;
      arpPatternLength = 16;
      break;
    case 15:
      for(i = 0;i<16;++i) arpPattern[i] = 1;
      arpPatternLength = 16;
      break;
  } 
  

  if(forceRefresh)
  {
    uiClearLeds();
    uiSetLeds(0, 5, LED_MEDIUM);
    uiLeds[arpType] = LED_BRIGHT;
    uiSetLeds(13, 3, LED_MEDIUM);
  }
}

/////////////////////////////////////////////////////
// EDIT OCTAVE SHIFT
void editOctaveShift(byte keyPress, byte forceRefresh)
{
  if(keyPress >= 0 && keyPress <= 6)
  {
    arpOctaveShift = keyPress - 3;
    arpRebuild = 1;
    forceRefresh = 1;
  }

  if(forceRefresh)
  {
    uiClearLeds();
    uiSetLeds(0, 7, LED_DIM);
    uiLeds[3] = LED_MEDIUM;
    uiLeds[3 + arpOctaveShift] = LED_BRIGHT;
  }
}

/////////////////////////////////////////////////////
// EDIT OCTAVE SPAN
void editOctaveSpan(byte keyPress, byte forceRefresh)
{
  if(keyPress >= 0 && keyPress <= 3)
  {
    arpOctaveSpan = keyPress + 1;
    arpRebuild = 1;
    forceRefresh = 1;
  }

  if(forceRefresh)
  {
    uiClearLeds();
    uiSetLeds(0, 4, LED_DIM);
    uiLeds[arpOctaveSpan - 1] = LED_BRIGHT;
  }
}

/////////////////////////////////////////////////////
// EDIT ARP RATE
void editRate(byte keyPress, byte forceRefresh)
{
  byte rates[] = {
    SYNCH_RATE_1,
    SYNCH_RATE_2D,
    SYNCH_RATE_2,
    SYNCH_RATE_4D,
    SYNCH_RATE_4,
    SYNCH_RATE_8D,
    SYNCH_RATE_2T,
    SYNCH_RATE_8,
    SYNCH_RATE_4T,
    SYNCH_RATE_8T,
    SYNCH_RATE_16D,
    SYNCH_RATE_16,
    SYNCH_RATE_32,
    SYNCH_RATE_16T  };

  if(keyPress >= 0 && keyPress < 14)
  {
    synchPlayRate = rates[keyPress];
    forceRefresh = 1;
  }

  if(forceRefresh)
  {
    uiClearLeds();
    uiSetLeds(0, 14, LED_DIM);
    uiLeds[0] = LED_MEDIUM;
    uiLeds[2] = LED_MEDIUM;
    uiLeds[7] = LED_MEDIUM;
    uiLeds[11] = LED_MEDIUM;
    uiLeds[12] = LED_MEDIUM;
    for(int i=0; i<14; ++i)
    {
      if(synchPlayRate == rates[i]) 
      {
        uiLeds[i] = LED_BRIGHT;
        break;
      }
    }
  }
}

/////////////////////////////////////////////////////
// EDIT VELOCITY
void editVelocity(byte keyPress, byte forceRefresh)
{
  if(keyPress > 0 && keyPress <= 15)
  {    
    arpVelocity = (keyPress+1) * 8 - 1;
    forceRefresh = 1;
  }
  else if(keyPress == 0)
  {
    arpVelocity = 0;
    forceRefresh = 1;
  }

  if(forceRefresh)
  {
    uiClearLeds();
    int z = 0;
    if(arpVelocity > 0)
      z = (arpVelocity+1)/8 - 1;
    uiSetLeds(0, z, LED_MEDIUM);
    uiLeds[z] = LED_BRIGHT;
  }  
}

/////////////////////////////////////////////////////
// EDIT GATE LENGTH
void editGateLength(byte keyPress, byte forceRefresh)
{
  if(keyPress >= 0 && keyPress <= 14)
  {    
    arpGateLength = keyPress + 1;
    forceRefresh = 1;
  }
  else if(keyPress == 15)
  {
    arpGateLength = 0;
    forceRefresh = 1;
  }
  if(forceRefresh)
  {
    uiClearLeds();
    if(arpGateLength > 0)
    {
      uiSetLeds(0, arpGateLength, LED_MEDIUM);
      uiLeds[arpGateLength - 1] = LED_BRIGHT;
    }
    else
    {
      uiSetLeds(0, 16, LED_MEDIUM);
      uiLeds[15] = LED_BRIGHT;
    }
  }    
}

/////////////////////////////////////////////////////
// EDIT NOTE INSERT MODE
void editInsertMode(byte keyPress, byte forceRefresh)
{
  int i,j,note;
  switch(keyPress)
  {
     case 0: case 1: case 2: case 3: case 4:  
        arpInsertMode = keyPress;
        arpRebuild = 1;
        forceRefresh = 1;
        break;
     case 10:
         arpChordLength=2+random(3);
         for(i=0; i<arpChordLength; ++i)
         {
            for(;;)
            {
              note = 48+random(12); 
              for(j = 0; j<i; ++j)
              {
                if(ARP_GET_NOTE(arpChord[j]) == note)
                  break;
              }
              if(j>=i)
                break;
            }           
            arpChord[i] = ARP_MAKE_NOTE(note,64+random(64));
         }
         arpRebuild = 1;
         break;
     case 11: // MIN7
        arpChord[0] = ARP_MAKE_NOTE(48,127);       
        arpChord[1] = ARP_MAKE_NOTE(51,127); 
        arpChord[2] = ARP_MAKE_NOTE(55,127);
        arpChord[3] = ARP_MAKE_NOTE(58,127);
        arpChordLength = 4;
        arpRebuild = 1;
        break;
     case 12: // MAJ7
        arpChord[0] = ARP_MAKE_NOTE(48,127);       
        arpChord[1] = ARP_MAKE_NOTE(52,127); 
        arpChord[2] = ARP_MAKE_NOTE(55,127);
        arpChord[3] = ARP_MAKE_NOTE(59,127);
        arpChordLength = 4;
        arpRebuild = 1;
        break;
     case 13: // DOM7
        arpChord[0] = ARP_MAKE_NOTE(48,127);       
        arpChord[1] = ARP_MAKE_NOTE(52,127); 
        arpChord[2] = ARP_MAKE_NOTE(55,127);
        arpChord[3] = ARP_MAKE_NOTE(58,127);
        arpChordLength = 4;
        arpRebuild = 1;
        break;
     case 14: // MIN
        arpChord[0] = ARP_MAKE_NOTE(48,127);       
        arpChord[1] = ARP_MAKE_NOTE(51,127);       ;       
        arpChord[2] = ARP_MAKE_NOTE(55,127);       ;       
        arpChordLength = 3;
        arpRebuild = 1;
        break;
     case 15: // MAJ
        arpChord[0] = ARP_MAKE_NOTE(48,127);       
        arpChord[1] = ARP_MAKE_NOTE(52,127);       ;       
        arpChord[2] = ARP_MAKE_NOTE(55,127);       ;       
        arpChordLength = 3;
        arpRebuild = 1;
        break;
  }

  if(forceRefresh)
  {
    uiClearLeds();
    uiSetLeds(0, 5, LED_DIM);
    uiLeds[arpInsertMode] = LED_BRIGHT;
    uiSetLeds(10, 6, LED_MEDIUM);
  }
}

/////////////////////////////////////////////////////
// EDIT SYNCH MODE AND TEMPO
void editTempoSynch(byte keyPress, byte forceRefresh)
{
  switch(keyPress)
  {
  case 0: // Toggle MIDI synch
    synchToMIDI = !synchToMIDI;
    forceRefresh = 1;
    break;
  case 1: // Toggle MIDI clock send
    if(synchSendMIDI)
    {
      synchSendEvent |= SYNCH_SEND_STOP;
      synchSendMIDI = 0;
    }
    else
    {
      synchSendEvent |= SYNCH_SEND_START;
      synchSendMIDI = 1;
    }
    forceRefresh = 1;
    break;
  case 14: // Manual tempo increment
    if(!synchToMIDI && synchBPM > 20)
    {
      synchSetTempo(synchBPM-1);
      forceRefresh = 1;
    }
    break;
  case 15: // Manual tempo decrement
    if(!synchToMIDI && synchBPM < 300)
    {
      synchSetTempo(synchBPM+1);
      forceRefresh = 1;
    }
    break;
  }

  // 0123456789012345
  // MS-HTTTT-UUUU-v^
  // TODO
  if(forceRefresh)
  {
    if(synchToMIDI)
    {
      uiSetLeds(0,16,LED_DIM);
      uiLeds[0] = LED_BRIGHT;
      uiLeds[1] = synchSendMIDI ? LED_BRIGHT : LED_MEDIUM;                                                                                                                                                                                                                                                            
      uiLeds[2] = LED_OFF;
      uiLeds[8] = LED_OFF;
      uiLeds[13] = LED_OFF;
    }
    else
    {
      byte bpmH = synchBPM/100;
      byte bpmT = (synchBPM % 100) / 10;
      byte bpmU = (synchBPM % 10);
      uiLeds[0] = LED_MEDIUM;
      uiLeds[1] = synchSendMIDI ? LED_BRIGHT : LED_MEDIUM;
      uiLeds[2] = LED_OFF;
      if(bpmH>2) uiLeds[3] = LED_BRIGHT;
      else if(bpmH>1) uiLeds[3] = LED_MEDIUM;
      else uiLeds[3] = LED_DIM;
      uiLeds[4] = (!!(bpmT & 0x08))? LED_MEDIUM : LED_DIM;
      uiLeds[5] = (!!(bpmT & 0x04))? LED_MEDIUM : LED_DIM;
      uiLeds[6] = (!!(bpmT & 0x02))? LED_MEDIUM : LED_DIM;
      uiLeds[7] = (!!(bpmT & 0x01))? LED_MEDIUM : LED_DIM;
      uiLeds[8] = LED_OFF;
      uiLeds[9] = (!!(bpmU & 0x08))? LED_MEDIUM : LED_DIM;
      uiLeds[10] = (!!(bpmU & 0x04))? LED_MEDIUM : LED_DIM;
      uiLeds[11] = (!!(bpmU & 0x02))? LED_MEDIUM : LED_DIM;
      uiLeds[12] = (!!(bpmU & 0x01))? LED_MEDIUM : LED_DIM;
      uiLeds[13] = LED_OFF;
      uiLeds[14] = LED_BRIGHT;
      uiLeds[15] = LED_BRIGHT;      
    }
  } 
}

/////////////////////////////////////////////////////
// EDIT MIDI OUTPUT CHANNEL
void editMidiChannel(byte keyPress, byte forceRefresh)
{
  // 0123456789012345
  // DDDOXXXXXXXXXXXX        
  if(keyPress >= 0 && keyPress <= 15)
  {
    if((midiSendChannel != keyPress) && arpStopNote)
    {
      midiWrite(MIDI_MK_NOTE_OFF, arpStopNote, 0, 2, millis());
      arpStopNote = 0;
    }
    midiSendChannel = keyPress;
    forceRefresh = 1;
  }

  if(forceRefresh)
  {
    uiClearLeds();
    uiSetLeds(0, 16, LED_DIM);
    uiLeds[midiSendChannel] = LED_BRIGHT;
  }
}

/////////////////////////////////////////////////////
// EDIT NOTE TRANSPOSE
void editTranspose(byte keyPress, byte forceRefresh)
{
  // 0123456789012345
  // DDDOXXXXXXXXXXXX        
  if(keyPress >= 0 && keyPress <= 15)
  {
    arpTranspose = keyPress - 3;
    arpRebuild = 1;
    forceRefresh = 1;
  }

  if(forceRefresh)
  {
    uiClearLeds();
    uiSetLeds(0, 16, LED_DIM);
    uiLeds[3] = LED_MEDIUM;
    uiLeds[arpTranspose + 3] = LED_BRIGHT;
  }
}

/////////////////////////////////////////////////////
// EDIT RUN
void editRun(unsigned long milliseconds)
{
  byte forceRefresh = 0;

  // Capture any key pressed on the data entry keypad
  char dataKeyPress = uiDataKey;
  if(dataKeyPress != NO_VALUE)
  {
    // reset the timeout period after which the 
    // display will revert to the pattern view
    uiDataKey = NO_VALUE;
    editRevertTime = milliseconds + EDIT_REVERT_TIME;
  }

  // Capture any key pressed on the data entry keypad  
  char menuKeyPress = uiMenuKey;
  if(menuKeyPress != NO_VALUE)
  {
    uiMenuKey = NO_VALUE;
    if(menuKeyPress != editMode)
    {
      // change to a new edit mode, so 
      // screen needs to be refreshed
      editMode = menuKeyPress;
      forceRefresh = 1;
    }
    editRevertTime = milliseconds + EDIT_REVERT_TIME;
  }

  // check if we timed out user input and should revert
  // to pattern edit mode  
  if(editRevertTime > 0 && editRevertTime < milliseconds)
  {
    editRevertTime = 0;
    if(editMode != EDIT_MODE_PATTERN)
    {
      // revert back to pattern edit mode
      editMode = EDIT_MODE_PATTERN;
      forceRefresh = 1;
    }
  }

  // run the current edit mode
  switch(editMode)
  {
  case EDIT_MODE_PATTERN_LENGTH:
    editPatternLength(dataKeyPress, forceRefresh);
    break;
  case EDIT_MODE_ARP_TYPE:
    editArpType(dataKeyPress, forceRefresh);
    break;    
  case EDIT_MODE_OCTAVE_SHIFT:
    editOctaveShift(dataKeyPress, forceRefresh);
    break;
  case EDIT_MODE_OCTAVE_SPAN:
    editOctaveSpan(dataKeyPress, forceRefresh);
    break;
  case EDIT_MODE_RATE:
    editRate(dataKeyPress, forceRefresh);
    break;
  case EDIT_MODE_VELOCITY:
    editVelocity(dataKeyPress, forceRefresh);
    break;    
  case EDIT_MODE_GATE_LENGTH:
    editGateLength(dataKeyPress, forceRefresh);
    break;    
  case EDIT_MODE_INSERT:
    editInsertMode(dataKeyPress, forceRefresh);
    break;    
  case EDIT_MODE_TEMPO_SYNCH:
    editTempoSynch(dataKeyPress, forceRefresh);
    break;    
  case EDIT_MODE_CHANNEL:
    editMidiChannel(dataKeyPress, forceRefresh);
    break;    
  case EDIT_MODE_TRANSPOSE:
    editTranspose(dataKeyPress, forceRefresh);
    break;        
  case EDIT_MODE_PATTERN:
  default:
    editPattern(dataKeyPress, forceRefresh);
    break;    
  }    
}    

////////////////////////////////////////////////////////////////////////////////
//
//
//
// HEARTBEAT
//
//
//
////////////////////////////////////////////////////////////////////////////////
#define P_HEARTBEAT        8
#define HEARTBEAT_PERIOD 500
unsigned long heartbeatNext;
byte heartbeatStatus;

////////////////////////////////////////////////////////////////////////////////
// HEARTBEAT INIT
void heartbeatInit()
{
  pinMode(P_HEARTBEAT, OUTPUT);     
  heartbeatNext = 0;
  heartbeatStatus = 0;
}

////////////////////////////////////////////////////////////////////////////////
// HEARTBEAT RUN
void heartbeatRun(unsigned long milliseconds)
{
  if(milliseconds > heartbeatNext)
  {
    digitalWrite(P_HEARTBEAT, heartbeatStatus);
    heartbeatStatus = !heartbeatStatus;
    heartbeatNext = milliseconds + HEARTBEAT_PERIOD;
  }
}

////////////////////////////////////////////////////////////////////////////////
//
//
// SETUP
//
//
////////////////////////////////////////////////////////////////////////////////
void setup() {                

  midiInit();
  arpInit();
  heartbeatInit();
  editInit(); 

  // initialise the basic UI last, since this will 
  // start up the refresh interrupt
  cli();
  synchInit();
  uiInit();
  sei();
}

void loop() 
{
  unsigned long millseconds = millis();
  synchRun(millseconds);
  arpRun(millseconds);
  heartbeatRun(millseconds);
  uiRun(millseconds);
  editRun(millseconds);   
}



