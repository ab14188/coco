// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 16                 //image height
#define  IMWD 16                  //image width

typedef unsigned char uchar;      //using uchar as shorthand

on tile[0] : in port buttons = XS1_PORT_4E; //port to access xCore-200 buttons
on tile[0] : out port leds = XS1_PORT_4F;   //port to access xCore-200 LEDs

on tile[0] : void memoryManagerA(chanend, chanend[3], chanend[2]); 
on tile[1] : void memoryManagerB(chanend, chanend[3], chanend[2]);
on tile[1] : void workersA(chanend[3]);
on tile[1] : void workersB(chanend[3]);
uchar changePixel(uchar, int);  

char infname[]  = "test.pgm";     //put your input image path here
char outfname[] = "testout.pgm"; //put your output image path here

on tile[0] : port p_scl = XS1_PORT_1E;         //interface ports to accelerometer
on tile[0] : port p_sda = XS1_PORT_1F;

#define FXOS8700EQ_I2C_ADDR 0x1E  //register addresses for accelerometer
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6

struct Line{ // sturcture that holds a line of the image
  uchar characters[IMWD];
};

struct halfImage{ // structure that holds half of the image
  struct Line lines[IMHT/2];
};

void DataInStream(char infname[], chanend c_out)
{
  int res;
  uchar line[ IMWD ];
  printf( "DataInStream: Start...\n" );

  //Open PGM file
  res = _openinpgm( infname, IMWD, IMHT );
  if( res ) {
    printf( "DataInStream: Error openening %s\n.", infname );
    return;
  }

  //Read image line-by-line and send byte by byte to channel c_out
  for( int y = 0; y < IMHT; y++ ) {
    _readinline( line, IMWD );
    for( int x = 0; x < IMWD; x++ ) {
      c_out <: line[ x ];
    }
  }

  _closeinpgm();
  printf( "DataInStream:Done...\n" );
  return;
}

void buttonCommands(in port press, chanend toLEDs, chanend toDataOut, chanend toDist){
    int r;
    while(1){
        press when pinseq(15) :> r;
        press when pinsneq(15) :> r;
        if(r == 13){
            toDist <: r;
            toDataOut <: r;
            toLEDs <: r;
        }
        else if(r == 14){
          toLEDs <: r;
          toDist <: r;
        } 
    }
}

void lightLEDs(out port light, chanend fromButtons, chanend fromDataOut){
    int r, d_out;
    while(1){
        fromButtons :> r;
        if(r == 13) light <: 2;
        else if( r== 14) light <: 3;
        fromDataOut :> d_out;
        if (d_out == 0)light <: 0;
    }
}


void distributor(chanend c_in, chanend c_out, chanend fromAcc,  chanend toManagerA, chanend toManagerB, chanend fromButtons)
{
    uchar val;
    struct Line analyzed;
    struct halfImage first;
    struct halfImage second; 
    
    printf( "ProcessImage:Start, size = %dx%d\n", IMHT, IMWD );
    printf( "Waiting for button to be pressed...\n" );
    fromButtons :> int value;

    printf( "Processing...\n" );
    
    for( int y = 0; y < IMHT; y++ ) {   
        for( int x = 0; x < IMWD; x++ ) { 
            c_in :> val;  
            if(y < IMHT/2) first.lines[y].characters[x] = val;
            if(y >= IMHT/2) second.lines[y - IMHT/2].characters[x] = val;
        }
    }

    toManagerA <: first;
    toManagerB <: second; 

    while(1){
       select{ 
        case fromButtons :> int request :
          printf("received a request to output the file \n");
          if (request == 13) {
            toManagerB <: 1;
            toManagerA <: 1;
            toManagerB :> second;
            toManagerA :> first;
            for(int x = 0; x < IMHT; x++){
              if( x < IMHT/2) analyzed = first.lines[x];
              else analyzed = second.lines[x - IMHT/2];
              c_out <: analyzed;
            }
          }
          break;
        case fromAcc :> int tilted :
          printf("tiltedddddddddddddddddd\n");
          break;
        default:
          break;
      }
    }
}

int determineLiveN(char ab, int i, int atline, struct Line firstL, struct Line toAnalyze, struct Line thirdL){
  int liveN  = 0;
  if (ab == 'a' && atline == 0){
    if (thirdL.characters[i] == 255)             liveN++;
    if (i == 0 || i < IMWD - 1){
      if (toAnalyze.characters[i + 1] == 255)    liveN++;
      if (thirdL.characters[i + 1] == 255)       liveN++;
    }else if (i != 0){
      if (toAnalyze.characters[i - 1] == 255)    liveN++;
      if (thirdL.characters[i - 1] == 255)       liveN++;
    }
  } else if (atline == IMHT/2 - 1 && ab == 'b'){
    if (firstL.characters[i] == 255) liveN++;
    if (i == 0 || i < IMWD - 1){
      if (toAnalyze.characters[i + 1] == 255)    liveN++;
      if (firstL.characters[i + 1] == 255)       liveN++;
    }else if (i != 0){
      if (toAnalyze.characters[i - 1] == 255)    liveN++;
      if (firstL.characters[i - 1] == 255)       liveN++;
    }
  }else {
    if (thirdL.characters[i] == 255)             liveN++;
    if (firstL.characters[i] == 255)             liveN++;
    if (i > 0){
      if (firstL.characters[i - 1] == 255)         liveN++;
      if (thirdL.characters[i - 1] == 255)         liveN++;
      if (toAnalyze.characters[i - 1] == 255)      liveN++;
    }
    if (i < IMWD - 1){
      if (thirdL.characters[i + 1] == 255)         liveN++;
      if (firstL.characters[i + 1] == 255)         liveN++;
      if (toAnalyze.characters[i + 1] == 255)      liveN++;
    }
  }
  return liveN;
}

void workersA(chanend fromManagerA[3]){
  struct Line firstL;
  struct Line toAnalyze;
  struct Line thirdL;
  struct Line analyzed;

  while(1){
    for(int j = 0; j < IMHT/2; j++){
      if (j == 0) fromManagerA[0] :> toAnalyze;
      fromManagerA[1] :> thirdL;   
      for (int i = 0; i < IMWD; i++) {
        int liveN   = determineLiveN('a', i, j, firstL, toAnalyze, thirdL);
        uchar pixel = changePixel(toAnalyze.characters[i], liveN);
        analyzed.characters[i] = pixel; 
      }
      fromManagerA[0] <: analyzed;
      firstL    = toAnalyze;
      toAnalyze = thirdL;
    }
  }
}

void workersB(chanend fromManagerB[3]){
  struct Line firstL;
  struct Line toAnalyze;
  struct Line thirdL;
  struct Line analyzed;

  while(1){
    for(int j = 0; j < IMHT/2; j++){
      if (j == 0 ){
        fromManagerB[0] :> firstL;
        fromManagerB[1] :> toAnalyze;
      }
      if (j < IMHT/2 - 1)fromManagerB[2] :> thirdL;

      for (int i = 0; i < IMWD; i++) {
        int liveN   = determineLiveN('b', i, j, firstL, toAnalyze, thirdL); 
        uchar pixel = changePixel(toAnalyze.characters[i], liveN);
        analyzed.characters[i] = pixel; 
      }
      fromManagerB[0] <: analyzed;
      firstL    = toAnalyze;
      toAnalyze = thirdL;
    }
  }
}


uchar changePixel(uchar pixel, int liveN){
  if (pixel == 255){
    if (liveN < 2 || liveN > 3) pixel = 0;
  }
  else if (pixel == 0 && liveN == 3)pixel = 255;
  return pixel; 
}

void memoryManagerA(chanend fromDistributor, chanend toWorkerA[3], chanend toMemB[2]){
    struct halfImage firstHalf;
    struct halfImage new;
    struct Line firstOfB;
    struct Line analyzed;

    fromDistributor :> firstHalf;

    int atRound = 1;
    while(1){
      //-- took if out here --//
      toMemB[1] :> firstOfB;
      toMemB[0] <: firstHalf.lines[IMHT/2-1];

      for(int i = 0; i < IMHT/2; i++){ 
        if( i != 0 && i < IMHT/2 - 1){
          toWorkerA[1] <: firstHalf.lines[i+1] ;
        }else if(i == 0){
          toWorkerA[0] <: firstHalf.lines[i];
          toWorkerA[1] <: firstHalf.lines[i+1];
        }else if(i == IMHT/2 - 1){
          toWorkerA[1] <: firstOfB;
        }

        toWorkerA[0] :> analyzed;
        new.lines[i] = analyzed;
        select {
          case fromDistributor :> int output: 
            fromDistributor <: firstHalf;
            break;
          default:
            break;
        }
      }
      printf("A round %d\n", atRound);
      atRound++;
      firstHalf = new;
    }
}

void memoryManagerB(chanend fromDistributor, chanend toWorkerB[3], chanend toMemA[2]){
    struct halfImage secondHalf;
    struct halfImage new;
    struct Line lastOfA;
    struct Line analyzed;

    fromDistributor :> secondHalf;

    int atRound = 1;
    while(1){
      toMemA[1] <: secondHalf.lines[0]; 
      toMemA[0] :> lastOfA;

      for(int i = 0; i < IMHT/2; i++){ 
        if( i != 0 && i < IMHT/2 - 1){
          toWorkerB[2] <: secondHalf.lines[i+1] ;
        }else if(i == 0){
          toWorkerB[0] <: lastOfA;
          toWorkerB[1] <: secondHalf.lines[i];
          toWorkerB[2] <: secondHalf.lines[i+1];
        }
        toWorkerB[0] :> analyzed;
        new.lines[i] = analyzed;
        
        select {
          case fromDistributor :> int output:
            fromDistributor <: secondHalf;
            break;
          default:
            break;
        }
      }
      printf("B round %d\n", atRound);
      atRound++;
      secondHalf = new;
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in, chanend fromButtons, chanend toLEDs)
{  
  int res;
  struct Line analyzed;
  printf( "DataOutStream:Start...\n" );

  while(1){
    //Compile each line of the image and write the image line-by-line
    select{
      case fromButtons :> int i:
        res = _openoutpgm( outfname, IMWD, IMHT );
        if( res ) {
          printf( "DataOutStream:Error opening %s\n.", outfname );
          return;
        }
        for( int y = 0; y < IMHT; y++ ) {
           c_in :> analyzed;
          _writeoutline(analyzed.characters, IMWD );
        }
        _closeoutpgm();
        toLEDs <: 0;
        printf( "DataOutStream:Done...\n" );
        break;
      default:
        break;
    }  
  }
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read accelerometer, send first tilt event to channel
//
/////////////////////////////////////////////////////////////////////////////////////////
void accelerometer(client interface i2c_master_if i2c, chanend toDist) {
  i2c_regop_res_t result;
  char status_data = 0;
  int tilted = 0;

  // Configure FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }
  
  // Enable FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }

  //Probe the accelerometer x-axis forever
  while (1) {

    //check until new accelerometer data is available
    do {
      status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
    } while (!status_data & 0x08);

    //get new x-axis tilt value
    int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

    //send signal to distributor after first tilt
    if (!tilted) {
      if (x>30) {
        tilted = 1 - tilted;
       // toDist <: tilted; // this is sending however not in a continuous fashion 
      }
    }
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////
int main(void) {

  i2c_master_if i2c[1];               //interface to accelerometer
  chan buttonsToDist, c_inIO, c_outIO, c_control, buttonsToLEDs, buttonsToDataOut, fromDataToLEDs, fromDistributorToManagerA, fromDistributorToManagerB;    //extend your channel definitions here
  chan managerAToWorker[3];
  chan managerBToWorker[3];
  chan memTomem[2];
  par {
    on tile[0] : i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing accelerometer data
    on tile[0] : accelerometer(i2c[0],c_control);        //client thread reading accelerometer data
    on tile[0] : DataInStream(infname, c_inIO);          //thread to read in a PGM image
    on tile[0] : DataOutStream(outfname, c_outIO, buttonsToDataOut, fromDataToLEDs);       //thread to write out a PGM image
    on tile[0] : distributor(c_inIO, c_outIO, c_control, fromDistributorToManagerA, fromDistributorToManagerB, buttonsToDist);//thread to coordinate work on image
    on tile[0] : lightLEDs(leds, buttonsToLEDs, fromDataToLEDs);
    on tile[0] : buttonCommands(buttons, buttonsToLEDs, buttonsToDataOut, buttonsToDist);
    on tile[0] : memoryManagerA(fromDistributorToManagerA, managerAToWorker, memTomem);
    on tile[1] : memoryManagerB(fromDistributorToManagerB, managerBToWorker, memTomem);
    on tile[1] : workersB(managerBToWorker);
    on tile[0] : workersA(managerAToWorker);
  }
  return 0;
}
