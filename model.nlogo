; ****************
; ** Extensions **
; ****************
extensions [matrix array]

; ********************
; ** Declare breeds **
; ********************
breed [borders border]   ; graphics: the colored border that indicates each neighborhood
breed [persons person]   ; the breed for residents
breed [clones clone]     ; graphics: highlight moving residents
breed [averages average] ; graphics: show average art/wealth of neighborhood

; ***********************
; ** Declare variables **
; ***********************
; The resident attributes
persons-own [
  neighborhood  ; the number of the neighborhood that the resident currently lives in
  d-art         ; the resident's desire for art
  d-wealth      ; the resident's desire for wealth
  a-art         ; the resident's art contribution
  a-wealth      ; the resident's wealth contribution

  myclone       ; graphics: to show when the person is moving
]

; The global variables
globals [
  num-of-nbh ; the number of neighborhoods to be simulated

  ; u and s are the normal distribution parameters
  d-wealth-u
  d-wealth-s
  d-art-u
  d-art-s
  a-wealth-u
  a-wealth-s
  a-art-u
  a-art-s

  ; graphics: the minimum and maximum art and wealth (for scaling the positions of the residents)
  a-art-min
  a-wealth-min
  a-art-max
  a-wealth-max

  ; graphics: width of the neigborhood border
  border-width

  ; Matrix withwealth(0), art(1) and number of successul moving(2), forced relocations(3)
  m-wealth-art-move-relocate
]

; ***********
; ** SETUP **
; ***********
to setup
  clear-all

  ; setup all global variables
  set num-of-nbh 5
  set d-wealth-u 0.5
  set d-wealth-s 0.2
  set d-art-u 0.5
  set d-art-s 0.2
  set a-wealth-u 5
  set a-wealth-s 1
  set a-art-u 5
  set a-art-s 1

  ; run setup functions for each breed
  setup-borders
  setup-patches
  setup-persons
  setup-averages

  ; graphics: distribute the residents according to their art and wealth contribution
  initiate-neighbourhood-distribution

;  show maximun-people-possible
  set  m-wealth-art-move-relocate matrix:make-constant count turtles  4 -1 ;Initialize the matrix
  ask persons [
    matrix:set  m-wealth-art-move-relocate who 0 a-wealth
    matrix:set  m-wealth-art-move-relocate who 1 a-art
    matrix:set  m-wealth-art-move-relocate who 2 0
    matrix:set  m-wealth-art-move-relocate who 3 0
  ]

  reset-ticks
end

; graphics: setup the colored patches where each patch is one neighborhood
to setup-patches
  foreach (range (num-of-nbh)) [ [x]->
    ask borders with [pxcor = x] [
      set pcolor 15 + x * 10
    ]
  ]
end

; graphics: create a white square within the neigborhood borders
to setup-borders
  set border-width 0.05
  foreach (range (num-of-nbh)) [ [x]->
    create-borders 1 [ setxy x 0 ]
    ask borders [
      set shape "full square"
      set size 1 - border-width
      set color white
    ]
  ]
end

; create residents for each neigborhood
to setup-persons
  ; create res-per-nbh amount of residents for each neighborhood, according to the slider
  ; we position them in the corner of the patch. They can be moved around the patch later to represent their attributes.
  foreach (range (num-of-nbh)) [ [x]->
    create-persons res-per-nbh [ setxy x 0 ]
  ]

  ; initialize the residents. These distributions can be changed later and correlations added.
  ask persons [
    ; set the neighborhood
    set neighborhood xcor

    ; graphics: initialize resident variables which are important for displaying them
    set shape "dot"
    set size 0.05
    set color 17 + 10 * neighborhood
    set myclone nobody

    ; Draw from the distributions
    let corr-vars1 corr-normal-random d-art-u d-art-s 0
    set d-art first corr-vars1
    set d-wealth last corr-vars1
    let corr-vars2 corr-normal-random a-art-u a-art-s attribute-correlation
    set a-art first corr-vars2
    set a-wealth last corr-vars2
  ]
end

; graphics: create the breed that shows the average art/wealth per neigborhood
to setup-averages

  foreach (range (num-of-nbh)) [ [x]->
    create-averages 1
    [
      set shape "x"
      set size 0.05
      set color black
      setxy x 0
    ]
  ]
end

; **************
; ** Go event **
; **************
; do one resident relocation
to go-once
  move-resident
  move-averages
  tick
end

; do multiple resident relocations until the button is pressed again
to go
  move-resident
  move-averages
  tick
end

; The relocation that happens in each timestep
to move-resident
  ;; choose a random non-empty neighborhood
  let nbh -1
  while [count persons with [neighborhood = nbh] <= 0] [
    set nbh random (num-of-nbh)
  ]

  ;; find a random resident in the neighborhood and move him to the one where he would be the happiest and is allowed to live
  ask one-of persons with [neighborhood = nbh] [
    let temp nbh
    set nbh relocate self false
  ]

  ;; If this breaches the maximum capacity of the neighborhood he pushes out the poorest one
  ;; This continues until no neighborhood is over maximum capacity.
  while [count persons with [neighborhood = nbh] > nbh-max-cap] [
    ask min-one-of persons with [neighborhood = nbh] [ [a-wealth] of self ] [
      set nbh relocate self true
    ]
  ]
end

; Moves the resident to the neighborhood that the agent is allowed to move to and is the most satisfied in.
; Returns the neighborhood.
; If forced is true then he cannot stay in the same neighborhood.
to-report relocate [resident forced]
  ;; calculate the satisfaction for each neighborhood
  let sat-vector n-values num-of-nbh [ i -> satisfaction self i ]
  ;; If the resident can't afford to live in a neighborhood he will not move there, defined as having satisfaction -1000
  ;; He can't afford it if its vacancy rate is less than the acceptable-vacancy-rate and he is below the average wealth of the neighborhood
  foreach (range (num-of-nbh)) [ [x]->
    ifelse ((forced and x = [neighborhood] of resident)
      or
      (x != [neighborhood] of resident and [a-wealth] of resident <= (average-wealth x)) and ((count persons with [neighborhood = x]) >= floor (nbh-max-cap * (1 - acceptable-vacancy-rate / 100)))
      )
    [
      ; he is not allowed to move to the neighborhood
      set sat-vector replace-item x sat-vector -1000
    ] [
      ; he is allowed to move to the neighborhood
    ]
  ]
  ;; find the neighborhood he can afford and is the happiest to go to
  ifelse max sat-vector = -1000 [
    ;; don't move
  ]
  [
    ; choose the neighborhood he is the happiest to live in and allowed to live in
    let max-nbh position (max sat-vector) sat-vector
    ; graphics: make the color of the resident bright again
    update-relocation-color (max-nbh)
    ; Update matrix m-wealth-art-move-relocate with new values for relocation/forced relocation
    update-relocation-details resident forced
    ; set the resident's new neighborhood
    set neighborhood max-nbh
    ; graphics: move the person graphics wise to a new neighborhood
    move-person-visual
  ]
  report [neighborhood] of resident
end

;updates the m-wealth-art-move-relocate with new details
;if forced is true then the number of forced relocations are updated.
;resident should be thw attribute who of the turtle that is relocated
to update-relocation-details [resident forced]

  ifelse(forced)
    [
      let number-of-forced-relocations matrix:get m-wealth-art-move-relocate [who] of resident 3
      set number-of-forced-relocations number-of-forced-relocations + 1
      matrix:set  m-wealth-art-move-relocate [who] of resident 3 number-of-forced-relocations
    ]
    [
        let number-of-success matrix:get m-wealth-art-move-relocate [who] of resident 2
        set number-of-success number-of-success + 1
        matrix:set  m-wealth-art-move-relocate [who] of resident 2 number-of-success
    ]
end

; ***********************
; ** Support functions ** ;TODO comment the functions of this section
; ***********************
; calculate residents satisfaction in neighborhood number nbh
to-report satisfaction [resident nbh ]
  let neighbor-set other persons with [neighborhood = nbh]
  report ([d-art] of resident * sum [a-art] of neighbor-set) + ([d-wealth] of resident * sum [a-wealth] of neighbor-set)
end

to-report average-wealth [nbh]
  if count persons with [neighborhood = nbh] = 0 [
    report 0
  ]
  report mean [a-wealth] of persons with [neighborhood = nbh]
end

to-report average-art [nbh]
  if count persons with [neighborhood = nbh] = 0 [
    report 0
  ]
  report mean [a-art] of persons with [neighborhood = nbh]
end

to-report std-wealth [nbh]
  if count persons with [neighborhood = nbh] < 2 [
    report 0
  ]
  report standard-deviation [a-wealth] of persons with [neighborhood = nbh]
end

to-report std-art [nbh]
  if count persons with [neighborhood = nbh] < 2 [
    report 0
  ]
  report standard-deviation [a-art] of persons with [neighborhood = nbh]
end

to-report min-wealth [nbh]
  report [a-wealth] of min-one-of persons with [neighborhood = nbh] [ [a-wealth] of self ]
end

; a truncated version of the normal distribution so that the number is always between 0 and 1. This implementation can be changed.
to-report random-tnormal [u s]
  let retval 2
  while [retval < 0 or retval > 1] [
    set retval random-normal u s
  ]
  report retval
end

; Draws two normally distributed numbers with mean=u and standard deviation s with a correlation coefficient corr
; see: https://math.stackexchange.com/questions/446093/generate-correlated-normal-random-variables
to-report corr-normal-random [u s corr]
  let x1 random-normal 0 1
  let x2 random-normal 0 1
  let x3 (corr * x1) + (sqrt (1 - corr * corr) * x2)

  let y1 u + (s * x1)
  let y2 u + (s * x3)
  report list y1 y2
end

; **************
; ** Graphics **
; **************
; graphics: distribute the residents according to their art and wealth contribution
to initiate-neighbourhood-distribution
  foreach range (num-of-nbh)
  [
    x ->
    move-in-neighborhood x
  ]
  ; move the average indicators in the neighborhood
  move-averages
end

; graphics: initially move all residents on a given patch to their location relative to their wealth and art contributions
to move-in-neighborhood [neighborhood-index]
  ; retrieve the patch of the neighborhood
  let neighborhood-patch one-of (patches with [pxcor = neighborhood-index])
  ; get max and min art and wealth
  set a-art-min [a-art] of min-one-of persons [a-art]
  set a-wealth-min [a-wealth] of min-one-of persons [a-wealth]
  set a-art-max [a-art] of max-one-of persons [a-art]
  set a-wealth-max [a-wealth] of max-one-of persons [a-wealth]
  ; update all residents on the patch
  ask persons-on neighborhood-patch
  [
    ; calculate the scale of the resident's wealth and art
    let wealth-plot-value ((a-wealth - a-wealth-min) / (a-wealth-max - a-wealth-min))
    let art-plot-value ((a-art - a-art-min) / (a-art-max - a-art-min))
    ; calculate new x and y positions
    let new_x (neighborhood - 0.5 + border-width + wealth-plot-value * (1 - 2 * border-width))
    let new_y (- 0.5 + border-width + art-plot-value * (1 - 2 * border-width))
    setxy new_x new_y
    ; move the residents clone
    if (myclone != nobody)
      [ ask myclone [ setxy new_x new_y ] ]
  ]
end

; graphics move the average indicators in the neighborhood
to move-averages
  ; for each neighborhood
  foreach (range (num-of-nbh)) [ [x]->
    let neighborhood-patch one-of (patches with [pxcor = x])
    ; get the average turtle on the given patch
    ask averages-on neighborhood-patch
    [
      ; calculate the scale of the average wealth and art
      let wealth-plot-value (((average-wealth x) - a-wealth-min) / (a-wealth-max - a-wealth-min))
      let art-plot-value (((average-art x) - a-art-min) / (a-art-max - a-art-min))
      ; set its x and y position
      setxy (x - 0.5 + border-width + wealth-plot-value * (1 - 2 * border-width)) (- 0.5 + border-width + art-plot-value * (1 - 2 * border-width))
    ]
  ]
end

; graphics: moves a resident graphics wise, also move its clone which indicates that it moved
to move-person-visual
  ; calculate the scale of the resident's wealth and art
  let wealth-plot-value ((a-wealth - a-wealth-min) / (a-wealth-max - a-wealth-min))
  let art-plot-value ((a-art - a-art-min) / (a-art-max - a-art-min))
  ; calculate new x and y positions
  let new_x (neighborhood - 0.5 + border-width + wealth-plot-value * (1 - 2 * border-width))
  let new_y (- 0.5 + border-width + art-plot-value * (1 - 2 * border-width))
  setxy new_x new_y
  ; move the residents clone
  if (myclone != nobody)
    [ ask myclone [ setxy new_x new_y ] ]
end

; graphics: update color brightness of a resident when it has relocated
to update-relocation-color [max-nbh]
  if (neighborhood != max-nbh)
    [
      if (myclone != nobody)
      [ ask myclone [ die ] ]
      let me nobody
      let newcolor (color - 2)
      hatch-clones 1
      [
        set me self
        set color newcolor
        set shape "dot"
        set size 0.05
      ]
      set myclone me
    ]
end

; **********
; ** Gini **
; **********
;TODO comment
to-report Gini [nbh]
  ;; reports the percentage of the population that has a percecentage of the wealth
  ;; indicative of the amount of wealth disparity in a population.

  let wealths [a-wealth] of persons with [neighborhood = nbh]
  let sorted-wealths sort wealths
  let total-wealth sum sorted-wealths

  let wealth-sum-so-far 0
  let index 0
  let num-people count persons with [neighborhood = nbh]
  let gini-reserve 0
  repeat num-people [
    set wealth-sum-so-far (wealth-sum-so-far + item index sorted-wealths)
    set index (index + 1)
    set gini-reserve gini-reserve + (index / num-people) - (wealth-sum-so-far / total-wealth)
  ]
  report gini-reserve

end

; **************
; ** Tracking **
; **************

to-report track-attributes

  ;returns aveage neighborhood wealth of fundamental agent types, rich, colonizer, poor-artist, and poor
  let quartile ceiling (count persons * .15) ;quartile size

  let wealthy max-n-of quartile persons [a-wealth] ; upper quartile of wealth
  let poor min-n-of quartile persons [a-wealth] ;lower quartile of wealth

  ; rich is of the upper quartile of wealth and has high desire for wealth
  let rich max-one-of wealthy [d-wealth]

  ; poor artist is poor with high desire for and attribute of art
  let poor-artists max-n-of (ceiling quartile * .25) poor [d-art] ;
  let poor-artist max-one-of poor-artists [a-art]

  ;colonizer is rich w high desire for art and low desire for wealth
  let colonizers min-n-of (ceiling quartile * .25) wealthy [d-wealth]
  let colonizer max-one-of colonizers [d-art]

  ;poor is of the lower quartile of wealth and has low art contribution and desire
  let poor-phillistines min-n-of (ceiling quartile * .25) poor [d-art]
  let poor-phillistine min-one-of poor-phillistines [a-art]

  ;returns an array of average wealth of the above agents
  let tracked array:from-list n-values 4 [-1]
  array:set tracked 0 average-wealth [neighborhood] of rich
  array:set tracked 1 average-wealth [neighborhood] of colonizer
  array:set tracked 2 average-wealth [neighborhood] of poor-artist
  array:set tracked 3 average-wealth [neighborhood] of poor-phillistine

  report tracked
end
@#$#@#$#@
GRAPHICS-WINDOW
210
10
1218
219
-1
-1
200.0
1
10
1
1
1
0
1
1
1
0
4
0
0
0
0
1
ticks
30.0

BUTTON
10
10
70
43
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
140
10
200
43
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

SLIDER
10
55
180
88
res-per-nbh
res-per-nbh
0
200
99.0
1
1
NIL
HORIZONTAL

PLOT
1235
10
1455
170
Number of residents in each neighborhood
time
#
0.0
10.0
96.0
102.0
true
false
"" ""
PENS
"default" 1.0 0 -2674135 true "" "plot count persons with [neighborhood = 0]"
"pen-1" 1.0 0 -955883 true "" "plot count persons with [neighborhood = 1]"
"pen-2" 1.0 0 -6459832 true "" "plot count persons with [neighborhood = 2]"
"pen-3" 1.0 0 -1184463 true "" "plot count persons with [neighborhood = 3]"
"pen-4" 1.0 0 -10899396 true "" "plot count persons with [neighborhood = 4]"

SLIDER
10
95
180
128
nbh-max-cap
nbh-max-cap
0
200
195.0
5
1
NIL
HORIZONTAL

PLOT
210
280
710
500
a-wealth
time
average wealth
0.0
10.0
4.0
6.0
true
false
"" ""
PENS
"default" 1.0 0 -2674135 true "" "plot average-wealth 0"
"pen-1" 1.0 0 -955883 true "" "plot average-wealth 1"
"pen-2" 1.0 0 -6459832 true "" "plot average-wealth 2"
"pen-3" 1.0 0 -1184463 true "" "plot average-wealth 3"
"pen-4" 1.0 0 -10899396 true "" "plot average-wealth 4"

PLOT
715
280
1215
500
a-art
time
average a-art
0.0
10.0
4.0
6.0
true
false
"" ""
PENS
"default" 1.0 0 -2674135 true "" "plot average-art 0"
"pen-1" 1.0 0 -955883 true "" "plot average-art 1"
"pen-2" 1.0 0 -6459832 true "" "plot average-art 2"
"pen-3" 1.0 0 -1184463 true "" "plot average-art 3"
"pen-4" 1.0 0 -10899396 true "" "plot average-art 4"

MONITOR
1235
175
1320
220
NIL
a-wealth-max
3
1
11

MONITOR
1330
175
1415
220
NIL
a-art-max
3
1
11

PLOT
5
375
208
505
min wealth
time
wealth
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -2674135 true "" "plot min-wealth 0"
"pen-1" 1.0 0 -955883 true "" "plot min-wealth 1"
"pen-2" 1.0 0 -6459832 true "" "plot min-wealth 2"
"pen-3" 1.0 0 -1184463 true "" "plot min-wealth 3"
"pen-4" 1.0 0 -10899396 true "" "plot min-wealth 4"

SLIDER
10
135
180
168
attribute-correlation
attribute-correlation
-1
1
-0.3
0.1
1
NIL
HORIZONTAL

BUTTON
75
10
135
43
NIL
go-once
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
210
225
270
270
avg-w 0
average-wealth 0
3
1
11

MONITOR
415
225
475
270
avg-w 1
average-wealth 1
3
1
11

MONITOR
615
225
672
270
avg-w 2
average-wealth 2
3
1
11

MONITOR
815
225
873
270
avg-w 3
average-wealth 3
3
1
11

MONITOR
1015
225
1072
270
avg-w 4
average-wealth 4
3
1
11

MONITOR
275
225
337
270
avg-art 0
average-art 0
3
1
11

MONITOR
480
225
542
270
avg-art 1
average-art 1
3
1
11

MONITOR
675
225
737
270
avg-art 2
average-art 2
3
1
11

MONITOR
875
225
937
270
avg-art 3
average-art 3
3
1
11

MONITOR
1075
225
1137
270
avg-art 4
average-art 4
3
1
11

MONITOR
340
225
405
270
population
count persons with [neighborhood = 0]
1
1
11

MONITOR
545
225
610
270
population
count persons with [neighborhood = 1]
17
1
11

MONITOR
740
225
805
270
population
count persons with [neighborhood = 2]
17
1
11

MONITOR
940
225
1007
270
population
count persons with [neighborhood = 3]
17
1
11

MONITOR
1140
225
1207
270
population
count persons with [neighborhood = 4]
17
1
11

SLIDER
10
175
180
208
acceptable-vacancy-rate
acceptable-vacancy-rate
1
100
1.0
1
1
%
HORIZONTAL

PLOT
-15
210
210
375
Succesful moves vs Forced relocation
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -5825686 true "" "plot sum matrix:get-column m-wealth-art-move-relocate 2"
"pen-1" 1.0 0 -7500403 true "" "plot sum matrix:get-column m-wealth-art-move-relocate 3"

PLOT
1232
235
1672
520
Gini
NIL
NIL
0.0
10.0
0.0
0.0
true
true
"" ""
PENS
"neighborhood 0" 1.0 0 -2674135 true "" "plot (Gini 0 / count persons with [neighborhood = 0]) * .5"
"neighborhood 1" 1.0 0 -955883 true "" "plot (Gini 1 / count persons with [neighborhood = 1]) * .5"
"neighborhood 2" 1.0 0 -6459832 true "" "plot (Gini 2 / count persons with [neighborhood = 2]) * .5"
"neighborhood 3" 1.0 0 -1184463 true "" "plot (Gini 3 / count persons with [neighborhood = 3]) * .5"
"neighborhood 4" 1.0 0 -10899396 true "" "plot (Gini 4 / count persons with [neighborhood = 4]) * .5"

PLOT
216
513
698
792
tracking
NIL
NIL
0.0
10.0
5.0
5.0
true
true
"" ""
PENS
"Rich" 1.0 0 -16777216 true "" "plot array:item track-attributes 0"
"Colonizer" 1.0 0 -11221820 true "" "plot array:item track-attributes 1"
"Poor-Artist" 1.0 0 -11085214 true "" "plot array:item track-attributes 2"
"Poor-Phillistine" 1.0 0 -955883 true "" "plot array:item track-attributes 3"

PLOT
-20
505
220
655
Art vs Wealth
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 0.1 2 -5298144 true "" "histogram matrix:get-column m-wealth-art-move-relocate 0"
"pen-1" 0.1 0 -14070903 true "" "histogram matrix:get-column m-wealth-art-move-relocate 1"

@#$#@#$#@
## WHAT IS IT?

This model aims to evaluate whether the possession and pursuit of cultural and economic capital are contributing factors towards neighborhood gentrification. Supply side theory shows that pursuit and possession of the latter is sufficient for gentrification to occur. However, it remains to be determined how the pursuit and possession of the former either inhibits or augments this dynamic.

## HOW IT WORKS

The model has 5 neighborhoods which are initialized with randomly generated residents. Each tick a random agent checks if he wants to relocate to another neighborhood and if he is more satisfied there and is allowed to move there, then he moves. If the neighborhood he moves to is overflowed after the new resident moved in the poorest resident in the
neighborhood is kicked out and he is forced to relocate. The loop continues
checking for overflows until no neighborhood is overflowed and then the timestep ends.
Each agent has the following attributes:
	a-art: cultural capital 
	a-wealth: economic capital 
	d-art: the desire to be around people with a-art
	d-wealth: the desire to be around people with a-wealth
The satisfaction of a resident in a neighborhood is defined as:
	sat = d-art * avg_art(neighborhood) + d-wealth * avg_wealth(neighborhood)
An agent is allowed to move into a neighborhood if his a-wealth is higher than avg_wealth(neighborhood) or if the vacancy rate of the neighborhood is higher than the acceptable-vacancy-rate.

## HOW TO USE IT

res-per-nbh is the number of agents in each neighborhood after setup.
nbh-max-cap is the maximum number of agents that are allowed in each neighborhood before it overflows.
attribute-correlation is the correlation coefficient between a-art and a-wealth of residents
acceptable-vacancy-rate is the percentage vacancy allowed in a neighborhood  before letting in residents with lower a-wealth than the average of the neighborhood.


## THINGS TO NOTICE

Make sure that there is always enough room for all the agents to live.

## THINGS TO TRY

The most interesting change in behavior is when changing the attribute-correlation

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

https://github.com/robervkts/Capita_Social_Simulation.git
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

full square
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -7500403 true true 0 0 300 300

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0.2
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
1
@#$#@#$#@
