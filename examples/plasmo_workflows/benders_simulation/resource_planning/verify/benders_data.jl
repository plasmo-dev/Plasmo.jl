B = ["B0", "B1", "B2", "B3"]
F =  ["F0","F1","F2","F3","F4","F5","F6","F7","F8","F9"]
S = ["S0", "S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S10","S11","S12","S13","S14","S15","S16","S17","S18","S19","S20","S21","S22","S23","S24","S25","S26","S27","S28","S29","S30"]

budget = 500.0

h = Dict()
h["B0"] = 200
h["B1"] = 200
h["B2"] = 200
h["B3"] = 200

c = Dict()
c[("B2", "B0")] =  1.0
c[("B0", "B3")] =  1.1
c[("B1", "B3")] =  1.8
c[("B2", "B3")] =  1.2
c[("B0", "B1")] =  1.6
c[("B3", "B2")] =  1.1
c[("B1", "B0")] =  1.7
c[("B3", "B0")] =  1.6
c[("B1", "B2")] =  1.4
c[("B3", "B1")] =  1.6
c[("B2", "B1")] =  1.6
c[("B0", "B2")] =  1.4

init = Dict()
init["B0"] =  19
init["B1"] =  25
init["B2"] =  15
init["B3"] =  0

closesets = Dict()
closesets["F0"] = ["B3"]
closesets["F1"] = ["B0"]
closesets["F2"] = ["B0","B1"]
closesets["F3"] = ["B1"]
closesets["F4"] = ["B0"]
closesets["F5"] = ["B1","B3"]
closesets["F6"] = ["B0","B1","B3"]
closesets["F7"] = ["B0"]
closesets["F8"] = ["B1"]
closesets["F9"] = ["B0"]

demscens = Dict()
demscens[("S7", "F2")] =  8.81738084926
demscens[("S2", "F0")] =  7.39142422878
demscens[("S30", "F2")] =  12.8469271257
demscens[("S30", "F8")] =  10.4371875318
demscens[("S3", "F1")] =  8.30470024877
demscens[("S16", "F5")] =  8.81503507348
demscens[("S30", "F6")] =  12.554627377
demscens[("S24", "F8")] =  5.23524529273
demscens[("S1", "F0")] =  7.05842422878
demscens[("S30", "F1")] =  7.63044164915
demscens[("S6", "F2")] =  8.48438084926
demscens[("S15", "F5")] =  8.48203507348
demscens[("S25", "F8")] =  5.56824529273
demscens[("S10", "F3")] =  6.93859128706
demscens[("S28", "F9")] =  7.3269108025
demscens[("S4", "F1")] =  8.63770024877
demscens[("S0", "F0")] =  6.72542422878
demscens[("S27", "F9")] =  6.9939108025
demscens[("S20", "F6")] =  6.87369821265
demscens[("S18", "F6")] =  6.20769821265
demscens[("S26", "F8")] =  5.90124529273
demscens[("S14", "F4")] =  7.09549213947
demscens[("S30", "F9")] =  9.6183435676
demscens[("S29", "F9")] =  7.6599108025
demscens[("S30", "F0")] =  8.54499336131
demscens[("S13", "F4")] =  6.76249213947
demscens[("S19", "F6")] =  6.54069821265
demscens[("S21", "F7")] =  4.78621822849
demscens[("S30", "F4")] =  14.6096936596
demscens[("S17", "F5")] =  9.14803507348
demscens[("S5", "F1")] =  8.97070024877
demscens[("S12", "F4")] =  6.42949213947
demscens[("S11", "F3")] =  7.27159128706
demscens[("S8", "F2")] =  9.15038084926
demscens[("S23", "F7")] =  5.45221822849
demscens[("S30", "F3")] =  9.28434999186
demscens[("S30", "F7")] =  12.4530542821
demscens[("S9", "F3")] =  6.60559128706
demscens[("S30", "F5")] =  13.7000960612
demscens[("S22", "F7")] =  5.11921822849

costscens = Dict()
costscens[("S7", "F2")] =  1.18728419327
costscens[("S2", "F0")] =  1.89729234216
costscens[("S30", "F2")] =  1.59806232015
costscens[("S30", "F8")] =  1.23733273293
costscens[("S3", "F1")] =  0.795904267414
costscens[("S16", "F5")] =  1.10234446334
costscens[("S30", "F6")] =  1.14127491017
costscens[("S24", "F8")] =  0.616112590853
costscens[("S1", "F0")] =  1.39729234216
costscens[("S30", "F1")] =  1.72843513522
costscens[("S6", "F2")] =  0.687284193269
costscens[("S15", "F5")] =  0.602344463339
costscens[("S25", "F8")] =  1.11611259085
costscens[("S10", "F3")] =  1.00419248647
costscens[("S28", "F9")] =  1.26631900148
costscens[("S4", "F1")] =  1.29590426741
costscens[("S0", "F0")] =  0.897292342163
costscens[("S27", "F9")] =  0.766319001484
costscens[("S20", "F6")] =  1.58738493928
costscens[("S18", "F6")] =  0.58738493928
costscens[("S26", "F8")] =  1.61611259085
costscens[("S14", "F4")] =  1.50879649731
costscens[("S30", "F9")] =  1.93568757332
costscens[("S29", "F9")] =  1.76631900148
costscens[("S30", "F0")] =  1.64613524026
costscens[("S13", "F4")] =  1.00879649731
costscens[("S19", "F6")] =  1.08738493928
costscens[("S21", "F7")] =  0.505947313864
costscens[("S30", "F4")] =  1.50649166415
costscens[("S17", "F5")] =  1.60234446334
costscens[("S5", "F1")] =  1.79590426741
costscens[("S12", "F4")] =  0.508796497315
costscens[("S11", "F3")] =  1.50419248647
costscens[("S8", "F2")] =  1.68728419327
costscens[("S23", "F7")] =  1.50594731386
costscens[("S30", "F3")] =  1.80807534828
costscens[("S30", "F7")] =  1.12260715956
costscens[("S9", "F3")] =  0.504192486475
costscens[("S30", "F5")] =  1.39061804486
costscens[("S22", "F7")] =  1.00594731386

baseArcs = collect(keys(costscens));
closeArcs = Vector()
for (k,v) in closesets
    for i = 1:length(v)
        push!(closeArcs,(v[i],k))
    end
end


for s in S
    for f in F
        if !((s,f) in keys(demscens))
           demscens[s,f] = 0;
        end
    end
end

for s in S
    for f in F
        if !((s,f) in keys(costscens))
           costscens[s,f] = 0;
        end
    end
end
