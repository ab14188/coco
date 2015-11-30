// COMS20001 - Cellular Automaton Farm - 

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"
  
#define  IMHT 64                 //image height  
#define  IMWD 64                 //image width

typedef unsigned char uchar;      //using uchar as shorthand

on tile[0] : in port buttons = XS1_PORT_4E; //port to access xCore-200 buttons
on tile[0] : out port leds = XS1_PORT_4F;   //port to access xCore-200 LEDs

on tile[1] : void memoryManagerA(chanend, chanend[3], chanend[2], chanend); 
on tile[1] : void memoryManagerB(chanend, chanend[3], chanend[2]);
on tile[1] : void workersA(chanend[3]);
on tile[1] : void workersB(chanend[3]);
int changePixel(int, int);  
int totalLive(uchar);

char infname[]  = "test64.pgm";     //put your input image path here
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
  uchar characters[IMWD/8];
};

struct halfImage{ // structure that holds half of the image
  struct Line lines[IMHT/2];
};

struct uLine{
  uchar characters[IMWD];
};

void DataInStream(char infname[], chanend c_out)
{
  int res;
  uchar line[ IMWD ];
  c_out :> int start;
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

void buttonCommands(in port press, chanend toDist){
  int r;
  while(1){
    press when pinseq(15) :> r;
    press when pinsneq(15) :> r;
    toDist <: r;
  }
}

void lightLEDs(out port light, chanend fromDataOut, chanend fromDist, chanend fromA){
  int r, d_out;
  while(1){
    select{
      case fromDataOut :> d_out:
        light <: d_out;
        break;
      case fromDist :> r:
        light <: r;
        break;
      case fromA :> r:
        light <: r;
        break;
    }
  }
}


void distributor(chanend c_in, chanend c_out, chanend fromAcc,  chanend toManagerA, chanend toManagerB, chanend fromButtons, chanend toLEDs)
{
    uchar val;
    struct uLine line;
    int value, command, start = 1, counter = 0;
    struct Line analyzed;
    struct halfImage first;
    struct halfImage second; 
    
    printf( "ProcessImage:Start, size = %dx%d\n", IMHT, IMWD );
    printf( "Waiting for button to be pressed...\n" );
    while(start){
        fromButtons :> command;
        if(command == 14){
          start = 0;
          c_in <: 1;
        }   
        else if(command == 13) printf("Press other button to start\n");    
    }
    
    toLEDs <: 1;
    for( int y = 0; y < IMHT; y++ ) {   
      for( int x = 0; x < IMWD; x++ ) { 
        c_in :> val;
        value = 0;
        if (val == 255) value = 1;
        if(y < IMHT/2) {
          if (value == 1) first.lines[y].characters[x/8] |= value << (x%8);
          else if (value == 0)first.lines[y].characters[x/8] &= ~(1 << (x%8));
        }
        else if(y >= IMHT/2){
          if (value == 1) second.lines[y - IMHT/2].characters[x/8] |= value << (x%8);
          else if (value == 0)second.lines[y - IMHT/2].characters[x/8] &= ~(1 << (x%8));
        } 
      }
    }

    toManagerA <: first;
    toManagerB <: second; 
    toLEDs <: 0;

    while(1){
       select{ 
        case fromButtons :> int request :
          if (request == 13) {
            toManagerB  <: request;
            toManagerA  <: request;
            c_out       <: request;
            toManagerB  :> second;
            toManagerA  :> first;

            for(int x = 0; x < IMHT; x++){
              if( x < IMHT/2) analyzed = first.lines[x];
              else analyzed = second.lines[x - IMHT/2];
              for (int i = 0; i<IMWD; i++) {
                if (((analyzed.characters[i/8] >> i%8)&1) == 1) line.characters[i] = 255;
                else line.characters[i] = 0;
              }
              c_out <: line;
            }
          }
          break;
        case fromAcc :> int pause:
          toManagerA <: pause;
          toManagerB <: pause;
          break;
      }
    }
}


int neighbours(int i, char exclusions, struct Line firstL, struct Line toAnalyze, struct Line thirdL){
  int liveN = 0, at    = i/8, shift = 0, last  = 0;

  if ((((thirdL.characters[i/8] >> (i%8)) &1) == 1) && (exclusions != 'b'))              liveN++;
  if ((((firstL.characters[i/8] >> (i%8)) &1) == 1) && (exclusions != 'a'))              liveN++;
  if (i < IMWD - 1){
    if (exclusions == 'b' || exclusions == 'a') last = 1;
    at      = i/8;
    shift   = (i%8 + 1);
    if (i%8 == 7) {
      at    = (i+1)/8;
      shift = 0;
    }
    if ((((thirdL.characters[at] >> shift)&1) == 1) && (exclusions != 'b'))              liveN++;
    if ((((firstL.characters[at] >> shift)&1)  == 1) && (exclusions != 'a'))             liveN++;
    if (((toAnalyze.characters[at] >> shift)&1) == 1)                                    liveN++;
  }                                                      
  if (i > 0 && last!=1){
    at      = i/8;
    shift   = (i%8 - 1);
    if (i%8 == 0){
      at    = (i-1)/8;
      shift = 7;
    } 
    if ((((thirdL.characters[at] >> shift)&1) == 1) && (exclusions != 'b'))              liveN++;
    if ((((firstL.characters[at] >> shift)&1) == 1) && (exclusions != 'a'))              liveN++;
    if (((toAnalyze.characters[at] >> shift)&1) == 1)                                    liveN++;
  }
  return liveN; 
}

int determineLiveN(char ab, int i, int  atline, struct Line firstL, struct Line toAnalyze, struct Line thirdL){
  char exclusions = 'c';
  if (atline == (IMHT/2 - 1) && ab == 'b')  exclusions = 'b';
  if (atline == 0 && ab == 'a')             exclusions = 'a';
  int liveN = neighbours(i, exclusions, firstL, toAnalyze, thirdL);
  return liveN;
}

void workersA(chanend fromManagerA[3]){
  struct Line firstL;
  struct Line toAnalyze;
  struct Line thirdL;
  struct Line analyzed;

  while(1){
    int totalL = 0;
    for(int j = 0; j < IMHT/2; j++){
      if (j == 0) fromManagerA[0] :> toAnalyze;
      fromManagerA[1] :> thirdL;   
      for (int i = 0; i < IMWD; i++) {
        int liveN = determineLiveN('a', i, j, firstL, toAnalyze, thirdL);
        int pixel = changePixel((toAnalyze.characters[i/8] >> (i%8)&1), liveN); 
        if (pixel == 1) analyzed.characters[i/8] |= pixel << (i%8);
        else if (pixel == 0)analyzed.characters[i/8] &= ~(1 << (i%8));
        totalL += pixel;
      }
      fromManagerA[0] <: analyzed;
      firstL    = toAnalyze;
      toAnalyze = thirdL;
    }
    fromManagerA[2] <: totalL;
  }
}

void workersB(chanend fromManagerB[3]){
  struct Line firstL;
  struct Line toAnalyze;
  struct Line thirdL;
  struct Line analyzed;

  while(1){
    int totalL = 0;
    for(int j = 0; j < IMHT/2; j++){
      if (j == 0 ){
        fromManagerB[0] :> firstL;
        fromManagerB[1] :> toAnalyze;
      }
      if (j < IMHT/2 - 1)fromManagerB[2] :> thirdL;

      for (int i = 0; i < IMWD; i++) {
        int liveN   = determineLiveN('b', i, j, firstL, toAnalyze, thirdL);
        int pixel = changePixel((toAnalyze.characters[i/8] >> (i%8)&1), liveN);
        if (pixel == 1) analyzed.characters[i/8] |= pixel << (i%8);
        else if (pixel == 0)analyzed.characters[i/8] &= ~(1 << (i%8));
        totalL += pixel;
      }
      fromManagerB[0] <: analyzed;
      firstL    = toAnalyze;
      toAnalyze = thirdL;
    }
    fromManagerB[2] <: totalL;
  }
}

int changePixel(int pixel, int liveN){
  if (pixel == 1){
    if (liveN < 2 || liveN > 3) pixel = 0;
  }
  else if (pixel == 0 && liveN == 3)pixel = 1;
  return pixel; 
}

void memoryManagerA(chanend fromDistributor, chanend toWorkerA[3], chanend toMemB[2], chanend toLEDs){
  struct halfImage firstHalf;
  struct halfImage new;
  struct Line firstOfB;
  struct Line analyzed;

  fromDistributor :> firstHalf;
  int atRound = 0;
  int output, liveNA, liveNB;
  while(1){
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
        case fromDistributor :> output:
          if (output == 13) {
            printf("data out at round %d\n", atRound);
            fromDistributor <: firstHalf;
          }
          else if(output == 1){
            toMemB[1] :> liveNB;
            printf("GAME PAUSED\n%d rounds have been processed so far\n", atRound); 
            printf("Total number of live cells is: %d\n", liveNA + liveNB);

            while(output){
              toLEDs <: 8;
              fromDistributor :> output;
            }
          toLEDs <: 0;
          }
          break;
        default:
          break;
      }
    }
    toWorkerA[2] :> liveNA;
    if(atRound != 0 && atRound % 2 == 0 && output != 13) toLEDs <: 4;
    else if(atRound % 2 != 0 && output != 13) toLEDs <: 0;
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

  int atRound = 0;
  int liveNB;
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
          if(output == 13) fromDistributor <: secondHalf;
          else if(output == 1){
            toMemA[1] <: liveNB;
            while(output) fromDistributor :> output;
          }
          break;
        default:
          break;
      }
    }
    toWorkerB[2] :> liveNB;
    atRound++;
    secondHalf = new;
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in, chanend toLEDs)
{  
  int res, i;
  struct uLine analyzed;
  printf( "DataOutStream:Start...\n" );

  while(1){
    //Compile each line of the image and write the image line-by-line
    select{
      case c_in :> i:
        if(i == 13){
          res = _openoutpgm( outfname, IMWD, IMHT );
          if( res ) {
            printf( "DataOutStream:Error opening %s\n.", outfname );
            return;
          }
          toLEDs <: 2;
          printf("Starting\n");
          for( int y = 0; y < IMHT; y++ ) {
            c_in :> analyzed;
            _writeoutline(analyzed.characters, IMWD );
          }
          _closeoutpgm();
          toLEDs <: 0;
          printf( "DataOutStream:Done...\n" );
        }
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
    if(x > 30){
        toDist <: 1;
    }else{
      toDist <: 0; 
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
  chan distToLEDs, AtoLEDs, buttonsToDist, c_inIO, c_outIO, c_control, fromDataToLEDs, fromDistributorToManagerA, fromDistributorToManagerB;    //extend your channel definitions here
  chan managerAToWorker[3];
  chan managerBToWorker[3];
  chan memTomem[2];
  par {
    on tile[0] : i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing accelerometer data
    on tile[0] : DataInStream(infname, c_inIO);          //thread to read in a PGM image
    on tile[0] : DataOutStream(outfname, c_outIO, fromDataToLEDs);       //thread to write out a PGM image
    on tile[0] : distributor(c_inIO, c_outIO, c_control, fromDistributorToManagerA, fromDistributorToManagerB, buttonsToDist, distToLEDs);//thread to coordinate work on image
    on tile[0] : lightLEDs(leds, fromDataToLEDs, distToLEDs, AtoLEDs);
    on tile[0] : buttonCommands(buttons, buttonsToDist);
    
    on tile[1] : accelerometer(i2c[0],c_control);        //client thread reading accelerometer data
    on tile[1] : memoryManagerA(fromDistributorToManagerA, managerAToWorker, memTomem, AtoLEDs);
    on tile[1] : memoryManagerB(fromDistributorToManagerB, managerBToWorker, memTomem);
    on tile[1] : workersB(managerBToWorker);
    on tile[1] : workersA(managerAToWorker);
  }
  return 0;
}
