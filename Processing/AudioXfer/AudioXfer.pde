// WAV file converter for Trinket audio project.  Works with
// 'AudioLoader' sketch on Arduino w/Winbond flash chip.
// For Processing 2.0; will not work in 1.5!

import processing.serial.*;

Serial port = null;
int     capacity, state = 0, index = 0;
boolean done = false;
byte[]  output;

// Wait for line from serial port, with timeout
String readLine(Serial p) {
  String s;
  int    start = millis();
  do {
    s = p.readStringUntil('\n');
  } while ((s == null) && ((millis() - start) < 3000));
  return s;
}

char readChar(Serial p) {
  int i;
  int start = millis();
  do {
    i = p.read();
  } while ((i < 0) && ((millis() - start) < 3000));
  return (char)i;
}

// Extract unsigned multibyte value from byte array
int uvalue(byte b[], int offset, int len) {
  int    i, x, result = 0;
  byte[] bytes = java.util.Arrays.copyOfRange(b, offset, offset + len);
  for (i=0; i<len; i++) {
    x = bytes[i];
    if (x < 0) x += 256;
    result += x << (i * 8);
  }
  return result;
}

void setup() {
  String s;

  size(200, 200); // Serial freaks out without a window :/

  // Locate Arduino running AudioLoader sketch.
  // Try each serial port, checking for ACK after opening.
  println("Scanning serial ports...");
  for (String portname : Serial.list()) {
    try {
      // portname = "/dev/tty.usbmodem1a1331"; // bypass scan
      port = new Serial(this, portname, 115200);
    } 
    catch (Exception e) { // Port in use, etc.
      continue;
    }
    print("Trying port " + portname + "...");

    if (((s = readLine(port)) != null) && s.contains("HELLO")) {
      println("OK");
      break;
    } else {
      println();
      port.stop();
      port = null;
    }
  }

  if (port != null) { // Find one?
    if (((s        = readLine(port))                != null)
      && ((capacity = Integer.parseInt(s.trim())) > 0)) {
      println("Found Arduino w/" + capacity + " byte flash chip.");
      selectInput("Select a file to process:", "fileSelected");
    } else {
      println("Arduino failed to initialize flash memory.");
      state = 4;
    }
  } else {
    println("Could not find connected Arduino running AudioLoader sketch.");
    state = 4;
  }
}

void fileSelected(File f) {
  if (f == null) {
    println("Cancel selected or window closed.");
  } else {
    println("Selected file: " + f.getAbsolutePath());
    byte input[] = loadBytes(f.getAbsolutePath());

    // Check for a few 'magic words' in the file
    if (java.util.Arrays.equals(java.util.Arrays.copyOfRange(input, 0, 4 ), "RIFF".getBytes())
      && java.util.Arrays.equals(java.util.Arrays.copyOfRange(input, 8, 16), "WAVEfmt ".getBytes())
      && (uvalue(input, 20, 2) == 1) ) {
      int chunksize  = uvalue(input, 16, 4), 
        channels   = uvalue(input, 22, 2), 
        rate       = uvalue(input, 24, 4), 
        bitsPer    = uvalue(input, 34, 2), 
        bytesPer   = uvalue(input, 32, 2), 
        bytesTotal = uvalue(input, 24+chunksize, 4), 
        samples    = bytesTotal / bytesPer;

      println("Processing sound file...\n"
        + "  " + channels + " channel(s)\n"
        + "  " + rate     + " Hz\n" +
        "  " + bitsPer  + " bits");

      if (samples > (capacity - 6)) samples = capacity - 6;
      output = new byte[samples + 6];
      output[0] = (byte)(rate >> 8);     // Sampling rate (Hz)
      output[1] = (byte)(rate);
      output[2] = (byte)(samples >> 24); // Number of samples
      output[3] = (byte)(samples >> 16);
      output[4] = (byte)(samples >> 8);
      output[5] = (byte)(samples);

      int index_in = chunksize + 28, index_out = 6, end = samples + 6;
      int c, lo, hi, sum, div;

      // Merge channels, convert to 8-bit
      if (bitsPer == 16) div = (channels * 256);
      else              div =  channels;
      while (index_out < end) {
        sum = 0;
        for (c=0; c<channels; c++) {
          if (bitsPer == 8) {
            lo = input[index_in++];
            if (lo < 0) lo += 256;
            sum += lo;
          } else if (bitsPer == 16) {
            lo = input[index_in++];
            if (lo < 0) lo += 256;
            hi = input[index_in++];
            sum += (hi + 128) * 256 + lo;
          }
        }
        output[index_out++] = (byte)(sum / div);
      }
      state = 1;
    }
  }
}

void draw() {
  if (state == 1) {
    port.bufferUntil('\n');
    print("Erasing flash...");
    port.write("ERASE");
    state = 2;
  } else if (state == 4) exit();
}

void serialEvent(Serial p) {
  char ch;

  switch (state) {
  case 2:
    String s;
    s = readLine(p);
    println(s);
    if (s.contains("READY")) {
      p.buffer(1);
      print("OK\nWriting...");
      p.write(output[index++]);
      state = 3;
    }
    break;
  case 3:
    ch = readChar(p);
    switch (ch) {
    case '.':
      break;
      
    case '!':
      println(index / 256);
      break;
      
    case 'X':
      print(ch);
      break;
    default:
      print('?');
    }

    if (index < output.length) {
      p.write(output[index++]);
    } else {
      state = 4;
    }
    break;
  }
}