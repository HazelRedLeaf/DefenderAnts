/*
 * Assignment 1 (XC-1A Concurrent Ant Defender Game)
 *
 *  Created on: 17 Oct 2014
 *      Author: kr13918, mm13354
 */

/////////////////////////////////////////////////////////////////////////////////////////
//
// COMS20001
// ASSIGNMENT 1
// CODE SKELETON
// TITLE: "LED Ant Defender Game"
//
/////////////////////////////////////////////////////////////////////////////////////////

#include <stdio.h>
#include <platform.h>
#include <print.h>
#include <stdlib.h>
#include <syscall.h>
#include <string.h>
#include <math.h>
#define BUFFER_SIZE 100

out port cled0 = PORT_CLOCKLED_0;
out port cled1 = PORT_CLOCKLED_1;
out port cled2 = PORT_CLOCKLED_2;
out port cled3 = PORT_CLOCKLED_3;
out port cledG = PORT_CLOCKLED_SELG;
out port cledR = PORT_CLOCKLED_SELR;
in port  buttons = PORT_BUTTON;
out port speaker = PORT_SPEAKER;

// --------------------------------------------------------------------------------------
const int LEFT      = 7;
const int RIGHT     = 14;
const int END       = 11;
const int PAUSE     = 13;
const int RESTART   = 9;
const int TERMINATE = -1;
// --------------------------------------------------------------------------------------

/////////////////////////////////////////////////////////////////////////////////////////
//
//  Helper Functions provided for you
//
/////////////////////////////////////////////////////////////////////////////////////////

// function to swap two integers
void swap(int &x, int &y)
{
  int tmp = x;
  x = y;
  y = tmp;
}


//DISPLAYS an LED pattern in one quadrant of the clock LEDs
int showLED(out port p, chanend fromVisualiser)
{
    unsigned int lightUpPattern;
    while (1)
    {
        fromVisualiser :> lightUpPattern;   //read LED pattern from visualiser process
        if(lightUpPattern == TERMINATE)
            return 0;
        p <: lightUpPattern;                //send pattern to LEDs
    }
    return 0;
}

//PROCESS TO COORDINATE DISPLAY of LED Ants
void visualiser(chanend fromUserAnt, chanend fromAttackerAnt, chanend toQuadrant0, chanend toQuadrant1, chanend toQuadrant2, chanend toQuadrant3)
{
    unsigned int userAntToDisplay = 11;
    unsigned int attackerAntToDisplay = 5;
    int i, j;

    while (1)
    {
        select
        {
            case fromUserAnt :> userAntToDisplay:
                cledG <: 1;
                break;
            case fromAttackerAnt :> attackerAntToDisplay:
                cledR <: 1;
                break;
        }

        // if user ant sends a signal to terminate, send a termination signal to all quadrants
        if (userAntToDisplay == TERMINATE)
        {
            toQuadrant0 <: TERMINATE;
            toQuadrant1 <: TERMINATE;
            toQuadrant2 <: TERMINATE;
            toQuadrant3 <: TERMINATE;
            return;
        }

        j = 16<<(userAntToDisplay%3);
        i = 16<<(attackerAntToDisplay%3);
        toQuadrant0 <: (j*(userAntToDisplay/3==0)) + (i*(attackerAntToDisplay/3==0)) ;
        toQuadrant1 <: (j*(userAntToDisplay/3==1)) + (i*(attackerAntToDisplay/3==1)) ;
        toQuadrant2 <: (j*(userAntToDisplay/3==2)) + (i*(attackerAntToDisplay/3==2)) ;
        toQuadrant3 <: (j*(userAntToDisplay/3==3)) + (i*(attackerAntToDisplay/3==3)) ;
    }
}

//WAIT function
void waitMoment(unsigned int time)
{
    timer tmr;
    uint waitTime;
    tmr :> waitTime;
    waitTime += time;
    tmr when timerafter(waitTime) :> void;
}

//PLAYS a short sound (pls use with caution and consideration to other students in the labs!)
void playSound(unsigned int wavelength, out port speaker)
{
    timer  tmr;
    int t, isOn = 1;
    tmr :> t;
    for (int i=0; i<2; i++)
    {
        isOn = !isOn;
        t += wavelength;
        tmr when timerafter(t) :> void;
        speaker <: isOn;
    }
}

//READ BUTTONS and send to userAnt
void buttonListener(in port b, out port spkr, chanend toUserAnt, chanend toController)
{
    int r;
    int gameStatus = 0; // 0=not running, 1=running
    while (1)
    {
        waitMoment(5000000);
        b when pinsneq(15) :> r;    // check if some buttons are pressed
        playSound(2000000,spkr);    // play sound
        if (r == END)               // if button pressed means termination
        {
            // play an awesome symphony, this is better than Beethoven!
            // ~XMOS dubstep
            for (int i = 1 ; i < 6 ; i++)
            {
                playSound(1000000*i,spkr);
                waitMoment(1000000);
            }
            toController <: TERMINATE;    // send controller termination signal
            return;
        }
        else if (r == PAUSE)        // if pause button is pressed
        {
            if (gameStatus == 0)    // if the game is not running
            {
                waitMoment(5000000);
                continue;
            }
            else                    // if the game is already running then stop the controller
            {
               toController <: PAUSE;      // send controller pause signal
                while (1)
                {
                    waitMoment(20000000);
                    b when pinsneq(15) :> r;
                    playSound(2000000,spkr);
                    waitMoment(20000000);
                    if(r == PAUSE)
                    {
                        toController <: PAUSE;
                        break;
                    }
                    else if (r == END)
                    {
                        toController <: TERMINATE;    // send controller termination signal
                        return;
                    }
                    else
                        continue;
                }
            }
        }
        else if (r == RESTART)      // if restart is pressed
        {
            if(gameStatus == 1)     // if the game is running
            {
                toController <: RESTART;
                gameStatus = 0;     // sets the game status to not running
            }
            waitMoment(30000000);
        }
        else                        // if the game is running and no termination/pause/restart is pressed
        {
            gameStatus = 1;
            toUserAnt <: r;         // send button pattern to userAnt
        }
    }
}


/////////////////////////////////////////////////////////////////////////////////////////
//
//  MOST RELEVANT PART OF CODE TO EXPAND FOR YOU
//
/////////////////////////////////////////////////////////////////////////////////////////

//DEFENDER PROCESS... The defender is controlled by this process userAnt,
//                  which has channels to a buttonListener, visualiser and controller
void userAnt(chanend fromButtons, chanend toVisualiser, chanend toController)
{
    unsigned int userAntPosition = 11;      //the current defender position
    int buttonInput;                        //the input pattern from the buttonListener
    unsigned int attemptedAntPosition = 0;   //the next attempted defender position after considering button
    int moveForbidden;                      //the verdict of the controller if move is allowed
    toVisualiser <: userAntPosition;        //show initial position
    int stopGame = 0;

    while (1)
    {
        select
        {
            case fromButtons :> buttonInput:

                if (buttonInput == RIGHT) attemptedAntPosition = userAntPosition + 1;
                if (buttonInput == LEFT)  attemptedAntPosition = userAntPosition + 11;

                //overlap
                attemptedAntPosition = attemptedAntPosition % 12;

                // check with controller if move can be made
                toController <: attemptedAntPosition;
                toController :> moveForbidden;
                if (moveForbidden == 0)                         // move can be done
                {
                    userAntPosition = attemptedAntPosition;     // update user's position
                    toVisualiser <: userAntPosition;            // light LED up
                }
                else if (moveForbidden == TERMINATE)            // signal for termination
                {
                    toVisualiser <: TERMINATE;
                    return;
                }
                else                                            // move is not allowed
                {
                    attemptedAntPosition = userAntPosition;
                    toVisualiser <: attemptedAntPosition;
                }
                break;

            case toController :> stopGame:                      // if the controller sends a signal for termination
                if (stopGame == -1)
                {
                    toVisualiser <: TERMINATE;                  // send a signal to shut down to visualiser
                    return;
                }
                else if (stopGame == RESTART)                   // if restarting
                {
                    userAntPosition = 11;                       //the current defender position
                attemptedAntPosition = 0;                       //the next attempted defender position after considering button
                    toVisualiser <: userAntPosition;
                }
                break;
        }
    }
}

//ATTACKER PROCESS... The attacker is controlled by this process attackerAnt,
//                  which has channels to the visualiser and controller
void attackerAnt(chanend toVisualiser, chanend toController)
{
    int moveCounter = 0;                    //moves of attacker so far
    unsigned int attackerAntPosition = 5;   //the current attacker position
    unsigned int attemptedAntPosition;      //the next attempted  position after considering move direction
    int currentDirection = 1;               //the current direction the attacker is moving
    int moveForbidden = 0;                  //the verdict of the controller if move is allowed
    toVisualiser <: attackerAntPosition;    //show initial position
    int stopGame = 0;                       // boolean to check if the game is stopped
    int speed = 15000000;                   // speed of the attacker

    while (1)
    {
            attemptedAntPosition = (attackerAntPosition + currentDirection + 12) % 12;

            toController <: attemptedAntPosition;
            toController :> moveForbidden;
            if (moveForbidden == TERMINATE)
            {
                return;
            }
            else if (moveForbidden == RESTART)
            {
                moveCounter = 0;
                attackerAntPosition = 5;
                attemptedAntPosition;
                currentDirection = -1;
                moveForbidden = 0;
                toVisualiser <: attackerAntPosition;
                stopGame = 0;
                speed = 15000000;
            }
            else  if ((moveForbidden == 1) ||
                ((moveCounter % 31) == 0) ||
                ((moveCounter % 37) == 0) ||
                ((moveCounter % 47) == 0))
            {
                currentDirection = - currentDirection;  // changing direction
            }
            else
            {
                attackerAntPosition = attemptedAntPosition;
                toVisualiser <: attackerAntPosition;
            }

            if ((attackerAntPosition == 0) || (attackerAntPosition == 10) || (attackerAntPosition == 11))   // game over
            {
                toController :> moveForbidden;

                printf("GAME OVER! Your score is: %d \n", moveCounter);
                if(moveForbidden == TERMINATE)
                    return;
                else if (moveForbidden == RESTART)
                {
                    moveCounter = 0;
                    attackerAntPosition = 5;
                    attemptedAntPosition;
                    currentDirection = -1;
                    moveForbidden = 0;
                    toVisualiser <: attackerAntPosition;
                    stopGame = 0;
                    speed = 15000000;
                }
            }
            waitMoment(speed);
            moveCounter++;
            if (moveCounter == 25)
                speed = 10000000;
            else if (moveCounter == 60)
                speed = 7000000;
            else if (moveCounter == 150)
                speed = 5000000;
    }
}

//COLLISION DETECTOR... the controller process responds to ¿permission-to-move¿ requests
//                      from attackerAnt and userAnt. The process also checks if an attackerAnt
//                      has moved to LED positions I, XII and XI.
void controller(chanend fromAttacker, chanend fromUser, chanend fromButtonListener)
{
    unsigned int lastReportedUserAntPosition = 11;      //position last reported by userAnt
    unsigned int lastReportedAttackerAntPosition = 5;   //position last reported by attackerAnt
    int attempt = 0;
    int stopGame = 0; // 0 = running, 1 = attacker finished, -1=terminate
    int pattern = 0;
    select
    {
        case fromUser :> attempt:   //start game when user moves
           fromUser <: 1;          //forbid first move
           break;

        case fromButtonListener :> attempt: // if the first button pressed was end/pause/restart
            if (attempt == TERMINATE)
            {
                fromAttacker :> attempt;
                fromAttacker <: -1;
                fromUser <: -1;
                return;
            }
            break;
    }

    while (1)
    {
        select
        {
        case fromButtonListener :> pattern:
            if (pattern == TERMINATE)
            {
                if (stopGame == 0) // if attacker is still running, accept his move.
                    fromAttacker :> attempt;
                fromAttacker <: -1;
                fromUser <: -1;
                return;
            }
            else if (pattern == PAUSE)
            {
                while(1)
                {
                    fromButtonListener :> pattern;
                    if (pattern == PAUSE)
                        break;
                    else if (pattern == TERMINATE)
                    {
                        if (stopGame == 0) // if attacker is still running, accept his move.
                            fromAttacker :> attempt;
                        fromAttacker <: -1;
                        fromUser <: -1;
                        return;
                    }
                    else
                        continue;
                }
            }
            else if (pattern == RESTART)
            {
                fromUser <: RESTART;
                if (stopGame == 0) // if attacker is still running, accept his move.
                    fromAttacker :> attempt;
                fromAttacker <: RESTART;
                stopGame = 0;
                select
                {
                    case fromButtonListener :> pattern:
                       if (stopGame == 0) // if attacker is still running, accept his move.
                           fromAttacker :> attempt;
                       fromAttacker <: -1;
                       fromUser <: -1;
                       return;
                       break;
                    case fromUser :> attempt:   //start game when user moves
                        fromUser <: 1;
                        break;
                }
            }
            break;
        case fromAttacker :> attempt:
            if (attempt!=lastReportedUserAntPosition)       //if the position attempted by the attacker is NOT occupied
            {
                fromAttacker <: 0;                          //allow attacker to move
                lastReportedAttackerAntPosition = attempt;  //update attacker's position
                if ((lastReportedAttackerAntPosition == 0)
                        || (lastReportedAttackerAntPosition == 10)
                        || (lastReportedAttackerAntPosition == 11)) //if attacker ended, set flag to 1
                    stopGame = 1;
            }
            else
            {
                fromAttacker <: 1;                          //don't allow attacker to move
            }
            break;
        case fromUser :> attempt:
             if (attempt!=lastReportedAttackerAntPosition)   //if the position attempted by the user is NOT occupied
            {
                fromUser <: 0;                              //allow user to move
                lastReportedUserAntPosition = attempt;      //update user's position
            }
            else
            {
                fromUser <: 1;                              //don't allow user to move
            }
            break;
        default:
            break;
        }
    }
}

//MAIN PROCESS defining channels, orchestrating and starting the processes
int main(void)
{
    chan buttonsToUserAnt,      //channel from buttonListener to userAnt
        userAntToVisualiser,    //channel from userAnt to Visualiser
        attackerAntToVisualiser,  //channel from attackerAnt to Visualiser
        attackerAntToController,  //channel from attackerAnt to Controller
        userAntToController,    //channel from userAnt to Controller
        buttonsToController; // channel for termination;
    chan quadrant0,quadrant1,quadrant2,quadrant3; //helper channels for LED visualisation

    par
    {
            //PROCESSES FOR YOU TO EXPAND
            on stdcore[1]: userAnt(buttonsToUserAnt,userAntToVisualiser,userAntToController);
            on stdcore[2]: attackerAnt(attackerAntToVisualiser,attackerAntToController);
            on stdcore[3]: controller(attackerAntToController, userAntToController, buttonsToController);

            //HELPER PROCESSES
            on stdcore[0]: buttonListener(buttons, speaker,buttonsToUserAnt, buttonsToController);
            on stdcore[0]: visualiser(userAntToVisualiser,attackerAntToVisualiser,quadrant0,quadrant1,quadrant2,quadrant3);
            on stdcore[0]: showLED(cled0,quadrant0);
            on stdcore[1]: showLED(cled1,quadrant1);
            on stdcore[2]: showLED(cled2,quadrant2);
            on stdcore[3]: showLED(cled3,quadrant3);
    }
    return 0;
}




