-- Looty SoftRes Standalone Test
-- Run with: lua SoftRes_test.lua
-- Prerequisites: Lua 5.1+ or LuaJIT
--
-- Instructions:
--   1. Get a softres.it WeakAuras export string
--   2. Paste it below as the value of SOFT_RES_STRING
--   3. Run: lua SoftRes_test.lua

local SOFT_RES_STRING = [[
!WA:2!D37cqsYr65HndMbe8M7HawShUdhpYRUHhWodqVdQQF3GAjU59mlMxO7E3f4aaNj7UYURet1vvxwvnZ24aozUXrkijksPvsuIupO0sks94OK4Q3socrcrrAlt5ifScgJIWrqByt6W3z7lmS8RG2X54pZ8VE0Dp7U3d7GHheyNPRoF))N)p(()ZSMU3f6E135z4KUrmFVWQD6X8yHopDNUXHr(dc(1D97sCn4gxXGeZjhs9ozjoTpZ3Bo(Z3Ig1QlNfeTW877TUxeLpFHEXEYMAHfnOE2loAP2HsoHEFl1U(XH018p1lxjVbLC8YXCs4sT6s8w)eQxu4cZFJLpS1(B0(WMR36WwRU8EhUYYB2A(cr8yQUXN722(hQMphTcZJfnxZWicp6PfZe81(oy(XF(v9D95lyUu1c4)B9GoTXkBvq(F))bRdIh(OMe3ahYmFaXRRJpFdozaT9WaANwR2C9137UQhFGpZlQZQRVx71BEBIhBab63QIhAJ3ZoMl)WHrddO8qAxFp7W3LscPTI4uV(ropYTGpbn6kE(E0vGckE8vgqyEBi(djEuXJ9iIliECXffpU4rg9jVhjoYXNVFGKxCUviXr(on7cRtxDMzMzM7a9ht9LD6671J1FUB113312)uVJEx8Vw3Up159Wp16uwa9OGlIFUn9MrRXcjDCP2o3XMgsIGzf15U2SWaxYWT7671XQuPQLnVBpyjQveNerMPJdL13j6LwH1137O7a)Bl)yEx6StnpZo4XB10aOhgRq6hASsCuKV3DzE985QfWN(U985DPkY1rbFswFpFovpxLpDDo3NhE0hWaonpI71P8qMV3pgN5DcSA78bhtPblhgq7g1eAtNvC9j29A21Leg(enhe7gXMBLq2BsFcXZn3kqbH)OteXL6fb)5TJdPh6rpHYpI)M(E0TTdFO7O43bAM4ZD7qQBpjhG4J2jKo4ekVP1swlz1juox7Wge4ZJUtyCNMYQf(8pH4IVxyCNoKUh3N7h7z37D74ZTP8dtPC3v)eQDFk3Y4a2nPUVN(z(96fsJMDkSmW4FM3x)HtyHSoU0Jex82qFiF47CX3tXP(Y7RRQ(ZVc(57W9JiruGuVYE7V36bpAe9MrhMH)w8rdEC1ZIJ8bcu3BWSJCwz54i)7i)I0b)hi)Cp2nP2Yc9JEB1d89IcUWkS(g757B7snAZICzE9FVKVTf7nPpz6hHvy((xR9oBV36VR8PVrCyeR3qXh99LFmzTFLLVw791d6qhIT)PsHfxD2PG)BMGlK5BsweY90KLc1yf(N7aCNVMhWEg8Kjp9qfd6HH6)q84QHgUWRg(N6ZTVbNeCRBO)dXf5HXDKnBKF3tuCQFVN8U3kIZ63NYd)ypnx)N)g3XM2jUxp50FR135GnU2o3cLKCbRMuG3)oRMS1UPhzanCUBfgqDD32oCU3pmUJSqhWP9y3SzRdwFNDsEyR4E9y38UhU6YTAFyR2l3ST4IRe7XI4XEYci(eIbDGn2u(7dS)e3tjddb5IhDl4Zqzp62XE6H7CbpgOm8eAB1N313M(vNQymZ(U3i(yZ9EPRz(fFP2fJ5UbFForrbHp)Z9CNs67VeZ)5(cBE51l1(Lp9nEUsbxioKUQwMZU(2njr0J46fQhPduJTx72jvO5PaNfLFtKUXhI)1kVPV)GzN6DAiMUQ4HMt8980IzU50FGsXvhPCM9idOz1GXSxAP5vF18ZL8u1dmUIX8epp)yVU05N7EP(lRckZLQT4CZX6z45hzWx6Wd1nwKd1BoddJSp7kgRYPKiQu)YcZRefoFH0HAHr6RfNJ6zpNES0X4kzAS56aAex21vUViCHfvpivf5QUSUhNr9iShQWslT0IgYHf8Z9xF5Y7T3(xBVvxxRUCoPU4o3B9)tOJsxYmlywWAYTZOMcCpBNKLETcCXJ803Y2)WqqmRtt5VcE(THrwpsx6RTSTTVx4RTl74wD5(UG0OvirrUsjHVwlO4HV2o(NUlXJSKF)(Ip0mI5eFyXhr8rfFSQIh66zui3jGtdPrR0Jytfxu8veF8XvG)opP4dn7u3wAvXgXEDdEXKPva3VpNggwWqARvbdBQBezrfVcnkM7P(cJN1iPSgpdwkGFq1SGuJBfgXjGU3osHYlpJ63RmZTL)w2Z)AqdpHENBvWOVvbJowfmiwfm4fly0VybJoflyqkUOEnxpI4wJmCwGx04YgCRfxeALr)Y(Wx2x(LDg7l7aFzh5xsg7ljWxsSwu1)WS1WqnP2up5AQNCW8)9W5VKTqyx0CPYj0IoGbxB7j(kIFSok1EZovNWUex6nNr97HZ8ErCIxOlSNewRALUoPjpVS(3VIMo9Y6F)kJtWEz5CbjvV8IfmmbYvAxinKygXffZCBL42ahYrY)uoHCEp4ptkTZfU5pXdDHHZoL4jMt8jo6dsnJqPYBRx4x5XGFwCs)X)(FMFMF1PMQ(T6q4yPFVla)8it6p(VPuPp)ut943glDXRoZmZo1mINCoXNAU7OCqa2Oe8CzTtxn1N)TABzA1OE56pV5BfnVMKzO2Zk(moVp1dSOCtoXMr9ICeZptWJ3x)P95W)k13DNT2V52FH93R9Y7i(b)mIpNJ4P(0tjTLmJbh3w(5qMnTzZT3CR2G5LxOvtJL1IT1wxkU0tlw4iXIhjEMFmXZEK4Y9elbg5jmL)RL8Flk)3soIYp0D9thhIFbrfoigUdHlQk(OIAI6IgINVzyaHFSZ7l)1kUupBq)xXLxBT7iF0QPM0j)8wsBIVI(dmBBQxZ9w)6R38DLprPd7LNDQSF8vMDQ3t(XM(QbZStf8y5Ea0NI2Q6auKyonyHuXCRscJKI24V212(YPF6YTGkOgOsl1(4IFOR(eIlk(dRTrTNpNQyUobT(uztyryz4kA7R26f(Dd(5)D(MFZFFXpS4feF(zNsS8mIvosCrXQVZtkwB2PeRp7uIneBk26D3EV9wV5HkNLeBlUQ4fLloID(rf7k2tS)tkoq8sIMIpQOLOT4AOfCIRpJ4gF6PeV87(uFPUVnsxd(SJzwwx87smpBc2U19E9Lb6)OzeBa1oyXjua4Bo0EOhzaR7HroCAOJVR9WGFGZRSQpn7utyaRlraN2LbM6mJ4vps8AIxxCrXpcpsrlVDRb((rogNuuC437jVR4Op2tliVZfeZeCLKDE0r1jQ2hsnUYvmYP7EV9BV9gVY8GmO3xThEnTTLp0DvF(qhMnvmd(jPlPurhrxH98wMFGEIJ16ibv0tzAzyWtpEpzK9rRTDRD3Uvlr)5eoZjyI3qCSWfe9j8aZof(IGJeFXJe8NqmtGv6KBXZF(OBsPigr4xDkr0D7138LwTNDCZ38eXjItdE04q6Y2GZduBQ9UKB6m6JyEoIHpI4nfFjXBT1N)LpAk4hXBp7uIV8Stj(JmM1K)x8aBn53sgm()F1ErKg9h8nxCU7LjEGnd3Bt7e)4I)OI3r8ht8hFgXFIze)eI)KIFYze)uZi(tj(tlSf3oTA)zKn2F2zNs8NBgXp9mI)8I)cIFgLzaIF2Je)fDe)LgrvV4V8dKYDXFLhiT6IFUSAZf)vdwyYkXlzwVuXNVO5Zxe1Jl(moI7akSf)8IFHuLYI)6kj5)IIFjq)7J1QPXASWbSWWVnv)k(BckDf)TYQUv832r8vf)YI)oQ(6V7ve)9e)kI7o7uI)(ZoL4FWStj(hkAl(hj(hl(NKvxM4F6jI)zI)5pqAS(K51yj(p(Bh1u3futPN(I)fIhx8Rk(1eV7qX)YzNs8RNveV4FL43yeH6IFtX)jpK4)uXmI)1ze7k(ptkOv8Bj(38aj9u8FUwyyTnAv5eNRBw8KUGWqHWr8V9(jSRLuyxvXmb)YSEPcUcbRLxYHsSPCPKj1EkTioA)jiKtPkQ)e3R7XCxCYfqVj(8lqgGELfskFBU5ep8r3jmYpq7WNsy9p5NtnaD99JwLeakunUIHs97c7S)(TpC72RV7HTwFNnm85gZ)k(XgCAxk7eQSopVXtfU08fmMFPNzlweDWZVWtz)Sl(8ZVOwGQdL7Z6UDeDWUKaJRy8LE7565Zn8GoWTG(RnyEgbegpCHVKCgD5lB02FvdltJLDDzeVUu5JF1Y1QAv71nUIr5AnkAvak32DPo(N6ASkZRRtAPkHLQKSuTC8JDTP8aIDOHFpG8ySPlPlJ4ACdMRDysnnRRRPvdznxUlZEa5uJv89JslLvvS9RMR97ht4P9qRagNfzCdI7XuEADnXEqv3L5d6q8sR1E(Ca7gpJwrJurlSI1LvCnoLyl9jdAdvxNopAGfUMSWBsI9ICPrYUPjlK513yzV(zB(k4CQSSgRqDJWX0gC)3K6z0KsYUixgRqfvxW4aWL6QS9GaIBMM3ejCwQsVQVRlHdLEvWNtxWx22(8buViSovQHeJIMQ6q4ESt85(XHgRq0onjhkfXcwuwWM(2qlV9Gaol03JAB0Yp2nD1PAc)HA1zdQR0oFJvyE2mV(PLSisTkP432H2VpuaCAUgDGVhRRXU0WqAU1ZQifOyJXwpVHevEJw(UHrSmC3frsCPItyjDdcpKM0dnkwsrXAuSKIHqYJcfUTph2iBB0kGKP1RJZ6s6DfuViMh11Ovx)yWRhJn5GSL0zF9KzFfKxnpl(EuGx1yhFEcXOwcFAPAtysORXQoKbbOmqjjexUkPO1lpi2LkxW00eJ1DPa3r6ORwsvuRWR7babdU0I8GE9KX(iTtsyOuRyBW40WiF(aJMmV(jZaZKfk1wHdCjE0q12rJwS(E0O0bbkkqtewJXpozUcUZACdsu6UMAjK4YQ5zlINnXnvMbZ9ek3yxs)4W0vuCIwwVtZ1)e6Ovz5WqsyiZlTw4KTSIzAlQ7GrQttsww2AjcxlRyq2G0Lga4Qms1gL4vlzxsz9cgj21M77n6yCnApQNDMESyYyuXRG06DGvU0sLmUAO3UYpXNNr4uyuhFEMHdstkReX2M4Ychq8GACDFxseZLACG)PzhiO0VYkY41zDJ85xk0yvIRBAPqrELvsdwXLyp6IZASWUSa3KTD1kJnDLQJq92X3FamBBjJYs6(AlCFD587RLQT4m6jYk5hNoWkJZ4kngNw75F6qJn5(rr(jvOeYsvPmUZwTI2YH1lkDqLYewgN7vTMat4YVjy5WbC)aN0nh1kHK3kf1m7Dirzyl2Hb8FqVDDFWF(0odP4vu8fRr4h3H4rnoG6ztsvruZe58QO2ASJVFa26TpL5zCDI7LoEykHUmQQOIIqVQdXLPezSc1JAZ6gLzNxPK11sO5g9iUUkcFAPsgTQLMM0Uh77LvIszuIsvtTOkxGdN6LvFxTYjtgvPAdkyybUqmfXcvpznTMIYDDAyKuUyc92Lsda9PPvbhF1uRMsJLWIFnp7HzgQ1lHlq100SaI02MWS8ts1VS0bvIbxvRKW)rtu3TkFyquoLe1lI8FvBmzjgTzdugfSvmORmTNq5NvlRPF0WiPsPeLReUn1lD(GKWAvrn4szAHPwQmWNhrCb71YiBQEjKAuZCYvuVHFRmwIupX6UQ6LAECi4rWLcHnm8HPfe3ovtXZCdAyKK1QfPtMbrI9OvRMWsSdZ37sHg7sonTyjlNf1BN7t9ImAsd9DpHM2PjRfLsATn5mVCt7KbMwyRp3Mt677Py6t5QsmySAD0IoBJv9H0lOpnJn71lHfSM2oLy3tjPAjB6pK4ASjqctBBKjSAjT44(mxIxKK4MUFb5fQP46wHqD7hdRnBrjNm0yvUFyyhTK1r8SylaX2K(RcoeBuoNBfA9rPLd3j1O6KzBNOxf1RGBpAumNxfTLMWNuSQiZtJZztXe9OOEfSA11wAYjDZSF98COOEfCrUH1OouOBI0IIR0nmh3DID9J9IgZHI6vqEYg1hZa4r8oOEfKnVXKSzCsUFuVm281RpIdfxZJQSIye)jQxbzTBO4Q20NpW)4lL3zI6vWnjnuCvT6sdaR1VhouuVQA9PUPP5ioumYcz1kyblJcvoLtcU)(tux7ZsDtZIJTCUIRVVTJVFpJ1bqvizKZuTkwTkjAsddOeUrtwumzuw8gf1YlBuuB(EwD2t2XI6vRH9HAxXni8qFV(gh4t66OK9L3XI6ANJQBAwhn)iVS1j4yr9AMyLg3JQZXTI61kQRJLfknlIffBFU(iuVAzSxumjAloUxEIuVk2lMwJ4xrooRQ1XIvBC)kYvYAi)KLIFAFExwOJXAusKtNS2EuVgYwyPvxh7jxR1(qCj0bJ0kGdcnYaPva9GqPRkl5QgY1AvEK6O8GqkX1DqA5rMoTZ(PLhjqxkm17I0QH8rAOrsRg64WLctfkMuT6iFHgZgKm1kY3lTXRJ0inYrRZK5OZLcn2NeLkwPgYzQrzzdAeSYFUEouVosQ0GuCDyBBwVq3WNhsooJfj1qomRsJon1(oaIKYrLRJJkTJR59CWasIQW0DWfXDWLMKlMt0dI6nWPH2PJSEqSfRVdirIKoEqkLgamWi07L3d1BGSPA3KBr9U0BW80cHyHrJYYvhz50WrPLGC)8COEdKzqJJqINdkafsBFCBGgciy739YXHgwjZa1gnPlQYwEd)UXzg4iVVgwS9OdOHSXiOipGgHsintHUF5((EPcVBG8SLulZB76gpG5jdTyAtHdmn4x3Gzt7q4CQRXgUmVix)UhNmlmXrh6QIFh6575qdtKVRY4GcUEuobNnmXPK2l9jb66K8DObYlnbCkg3ZHgMiJA5ZXem9EIr8BOboX1UUlfoeEmZt5brobrnmX1DnSe5m9Vj1MshqTvADlmUFb5lGXl6LfmJgMiJxLKD)NQ0aaylMdf36nWL)YOx62Gz95SvUHjs)1qxGYBmwX3J2LaPjyAdIDoIWJe7ejkgBbWuLzdsdKCQrxBxsQiT1j8ihaYfJvDy0ErKuyNAyIBC1oXUIlP7XoqzxXn2UpnLZTHfsk1iJSSx)ywOtAtH7L14EDaLRsRZ0walH29)LP9zj0Hv9DzH04u1snWHMg7Td4SudbErF(LoMNPTnr(sn4fGKeWO9Z1RIIvgnEfvBO3bxfn5Cdx)tLsTY61(YHDtntTAJAyD0EPTQFQZTTPE0osaW3LfMPkLXQuzIWuVc3xYrqjzQKwey1e)gYIZ0184uxQYU(wGPmjvt7Lsv0x)v4qRMGt4Q8yQRbKFnzMsnW6OD1iNVaYCqIZZOvTAJQ4Aa6CzYM0KvcO8WOBxFVWiUFilAyA1TWQRLUdB2DirGD8j2AMUqubxiQo(cXQ(XCsFQFCA5RHZMAOJtKaA6cxeb28FaNAtI8tNsAJIQIOW0YHCQBQmJEqMYaZNBW8St7lTxuvraaYQN66mFGez0MoiGM1vNQnQHvRUzEKkBt4KWVyCkhAfKlqJetRikvdWvhoLCCwIsjSOASx4dbRxb7yJO2gxN41pRKjt0RrtnQeJYv2csChLJAXPE2zIy6H(iTAmJtcL1AvIlzalc4)3iJaBt0)DtCvkVlWlhhfpWdCk3nbN1AMOJEMAESmvAvx)y7Hg7piXSTQn0cJRL4agiDVdjYrYnN2Q1WwDc6o2GWChdFBt0rCZQPbzkjmlBahWcLX)2SUzv9xTrdSV0(QSg5upnrBuxUmlN0jLgx436aZkpTSLWYAIGKY7tZ5JAoLYflQRqrT1Aq4uskoi3mhS)MiWnMA4QB57Mr7cySpWqLU(KmC0UFmCqhF5wN2qMFkte2ClliHv7ogaygeyEJwUKqNmm0nqXMAx9BtCLctyhNYAvhhR1lNtA8kmPSra1RKY2axJBuBCbj76hZ9uBWTZWfQhd1mBu9CWZvj3IAdOk46FAOdliP21WrNwOIcrPmIwpnhMpM1WLsn6XJSr5AErakE7scdjD5zweWQvV24COR671LsCP2Gne8m0Tg4g5gJOGPnNoWxk8wAjrA3GRFAbXJl1pjypgBr5(P9eo(0ynDDYGoWmBmfG(PozBwd7nnYWPGoj3AZaCo6ssbVXSokbqZUSQRprcJ5AYd7vxAw0MmRHZETozCpberjqa2Y9hHXTMjgVvtnMwTirCMh5sHaYtuLtTDjCsNKAGrz2uJT6vJLruUdNLf8itmuPM1rKsdbbjWW5GyEQMZAwySZS0HTU1Xdpv7Qp4Qqs5WTWwAljXiNlxoaKVwhaWkfKilmbaSSgh)QDP8UmjA)ViZndUGwyerSkxj3MVdaqkBdwvMoImXrUgEOSax1moYr2(xn2UFwQKfkw0cJazERzYa)4oKJZmBQJZgRjTpQLdJ6ApGWYejclm0VwLko(MiPnGzzgSqW6TkLcw)Y8oSijmi7ghMz0ubhnPboA9Bs7gdezvXLr5kPcy4)S0owCdclXuKrC81cX53sNcesqOUuOX1bRX7MUsIbMYQC1rJSwlkHpMAplTdJ1S04GiD7UvqgHVwyusS0EZVtCaZJASJVx)WisVEjkGWq2xmfqXCzvZYHqgz1IWsj9y(tuRyPQtiIM7W6HzLsgJtSQJSXAJMhpHqObupfWeSeznwOu(IAyy3W3pkiNK6HGVbPZC02jRkvgLbtU9AnAeLpkwaw1rEMgMteE5Lpf8mmtenkAMmWAmH4PHURmkINwOjlwAVyXDZsMd3HgRb4tLBKHuYgtWgh56Dm)yPTGoq(7MsKWXN2NTuI0kmP58nPaM8P4qy1ajRAuwZLit(8((rrupJDj8Omm5ymuSQmr4MQf5aJ4mtOIft4EQR9pg2SlX18e)0gg1CAPd9dE2MtbUMhNkohJqbc(oAT)A0axFoCOq0g9NzVmgielDSYvjOsIBsCclYNB8Izi6wOEwlTEMMuwFVuBaCzNKT0LXn2A30LUdcBtnw1vQAiDPpzxOQK7YcP8HxkesnNukkwinWclZ7647broJPdv5iovNluDf14ZxRSgFnKfnbjRCEtxRigAPYwJh1Gj6nDTIyKRkxCY7IMG301kQ9yTwznIE5S9Blcp0rN2xPDJfoYkoMFoJ7eDTI6yhvRSg0veN7Z3p6AfrgQYAK43Ie3HMg717Ht01kIMDx2Q8yorNyGv6OdlT2fGrZ1JX8JUwr0vPYAS2tSN6E4hDTIOBBL1bWiN33NJF01kIcSkRv2K1dL8(rtgKBrhjsA0vxHW7mb)ORveDbTmg8IOH9zeVj5jDTIyKElxmjSuUsiYiColt5QHKpDc4DajRJbt095IODNL16RrS5phFNlwdPcyAeMXsUZ155IOPQL14PEdolmkzxY4(pxRyvCJiMqKj(pRm8oDaHB)kBoMk2j6aDr0RMYLkpbFUpxhORvenFUCs0csDGgzGt7fKcRTxiNh0tWPy0)IYAd4Y7fDExUlI56AzTuXvz8UPraFCFOlIE(vwBnzEFO3G46MzThZsXYA9kzZiUTOuBPHoTyzMSvXAGXhrIL9gXPHwUyvKXrhuk0WWTaxTZHsQKHbBWY5vlpb)OlI6rkxP8KIG1K9KUi69DzTnj5JTX9Wl6IOXjL1UzK438izOrremGY6yvmQz)mPCKrDFUi64y5kJZrFEEpxeTJPmQ2nBG4NSd0fRJCrLBCVCG(uF3E5CGUiAFA5Xn38CCFUiAzt5Y5Jn0KDEUydCPdZfqhUFS9559Cr0eLYO)LAlHoFVNlIWnuwhBRRgdx5cEK4iWBfweXnR2T64YR2DL1IjUxwfkKvIHqHKUvdT5VSoclz8EEKmSQKjol1qEM6(CcUoPLf3runnjhr3Mhlt0lHECwUAE7yMGRWfrOklRXVlRnphWIMKR2frqZkRnJmJfWNR3ZLW0DRSgj8jYVnQZZfBGtLknMCALpj3NlHEQuUALXfYpM7ZLq8gkJrqGp8C8WTe6(C5QjPiiZ3ZJW4qK430N3pnUyfrmxlRtG0X91(6z80Ue6yAzn2LOqYvD8ZvmKIPt2WDhkVmxKsgDijrFPwjeC8YyA46h3pZInRpZgeaZtPrM4oPQPUzlZJIuF3lHj2CzeFOrTbyC3NlHifvwJjiKhK5mtEYEqxcZY8Yy6aYP0Uo07Jh0Lq0tkxV442xpQ7ZLWesTCTYJHhW57)CjmN5lxBYE3pM)ZLq3alJqwMAe)558CjmhwlRtX2Bqyz85(8CHUeEmakx3CIdUj7bDjmpwlR9anxU7Doorxcb0VSg17rsiVZXn6syEBwwh6YrCJUfH77XIOgRYIi20mDhUURXTiXz6LT955jr4znOCDlTpMWHSysEtxcrUQCTXJD2K8lUeEqdkJG7eZzaA4ESEqEALNvbz)1iVNZh61OKuoxeeRY1ssoA3WUCkzGrlaHS0LVI4YxDm3a61t6FwExOlHzpDznykqlYMSp0BVkKURQAwXSMYs5kw4XSjBSLpGebKN3e4HoqEj(PePLw5Y6kRTGhSz7uyD0jFEowXSMYByOF0cRzEhlnjWpgSb(6uEeTdNqtB7kyBJPZjNhhaHvuLM1kLkilFA1s6hlDke0fUwkmADm1LcXMmZb3dgw4matnkmgSsghWDTwm3JtlEYQvznBj4EDFciLVvxoKXekj0(hNUmvsbUAfZsAllA5YorL)OhahsIT7MzwBHDqX08XWypPf5PJIKcPfXO28ySUN8sGtEkvCjdh4ZtRJccdOo1t8DxNz8WypWvUVpTlmXINgV8e)Gu5)AszRJukR6tezYvaz(5is1rIK2B3wSqfi2GkJqPDGzkmoukw6CsWFTwU989dZSswhRMoLd9JDJGKtbYLooioXotCAH(bPTAqEYPprB1slkApo0d1WkunrFxFotPVtr4a5lqsuLPxqgon6tsH7q(3E8iP7x2HwnK4vS84v6lqjU(r5Y4sOFQI9J26ni5Rmw1FWaIoVj1kMs4svb(a(d168nCyHbkWG2asQtBJwhhJN9jOhqUqnqi6TYU(CBzguhHYgHjaoA0opU3B4Z9SjCfB4kOpBvmR1azMmRNtEKKtkr8xAXrAGgGXT7sVCtktTrW2468Hhh7MFLPbY8PJutU8fBhGQTLFqkFuDCT3k5Ka0L7FQNrtYGa4kMAujDnW5kc3C62bPP5JNZEqVGCRAy5KRlRXjhtLs6jWzFXEezxnqcaMPVOY0nj8((dDPk8ZslpUrsJ41YD8XXHm)s99ThM5CpcCcMilHAuTBmCNdPeymSVBgUNAnWDp6ioTlZwMMBq6SLolrQLgsm1MKnzeViPmRmGhdnjUvrhjI9aCB0zYFwKtRyw3u3W1BGNkgs8a4Q3SpS(TkN09yxfOcN6MwPYyLAKNYcNQcA(8KggoiJGoluqvxWf4PxF3mSa1nRITCTXmmlBEujxZtRfsF0jVrgOzjGdDXHG4KvJJY0rilqskOqSPxUvxFaxJvjCsAA5dLg581PbrcFsRa2y8X6tAemjQKk0Ph47JDQRwPLUbw6YjIB7kjO5pIEqrrwft8eVgZ7rK20agqC5nu9rA(Vdl(4(dD4YAsgqCj2EmmZOLqbelVu6s7Ok4ycJit)l5q4S0Kue4KtdByfZg4(W6AdUKuOqOOG8pGEl3SK)89NuBChwDTljVit5M918IK3bn2g3qEl5L2D4iu7MLe00qvesdIyDHoQBYoy9PIbkEd88c0pME5w(KJLefI6msmInr6dpfSoyHG9bc8UuOmUPg7r77s7gnQ8LgvXnvApz2GcAP7lrpztsiGCFUK0g6jlSNkMPksviY8pi)6vD0OK61hbV)DjEdnADCc(JqztMeyUAs7Y8JdbpxJJaZYvh4N01wCtO2JL0WGbLN2tDPuNo0rAhEwGIJ6ax4rPny1KgSMw(jN0LyNrMLLzIGiTNCRdueKaLFhMLzc)P2N0mHYubVMArltfW1RAMNNPqegOOy9BcAUtrMbQlU(vR2imbTC85rxUL88NANvxPLzIGSAO5XX965QYNFFAMbgU4HNrqxAOZLB5qcuN2NyUhDOuszqADqM5eOIaJML2oXCJCgASgJmWpD3ILjkTRUgOGM(rWn22LcnAgd3ujYO(LkaWYeL0ux7VxgnEgVOxC3JDZohq1bykZ63943GCA6M7KnFwORc9KSt4r8l1oElZI4csL85(Ug(mMhS5Pf1JLcbzfltlK7rdw4QKyy7ZBccZtcKauoCEPXNcSBemLheAkdI16EWD6OB6KZcz1WmMBc5I)U(8omB9jWiTMipNg6WMSGajhGKglfXLwwCjSkEs5iUbuxGrGRHWzIsoTmTWf3Qtc3quyyedWHntTqEAnGPWz3skilNdywMwiBC1XocxspFmUonJOMsQuzc(d1I118aWhIy9yYaUVpVpXlTTrMsnSIkw)vj8t0zNfScKwAKVqdABB5E2UuxwVurnwLqd(RxXkJAiWc(MKCBRlvpHrtlwemXCvFEqinN4ClZIittLKlbbBcNmaKa43lc8kniiJ0gnswqfYOl8YRXbp3L7QZeLoyKGTVoEoJDoXvrm6aoZRBgAyAVOJAG8kL9Yja(mYHGa6iKQRrFxIUziR7Xg7INjSvjbzgyifcJbce9pyrskQmNaJIidSoQhTD4qglH()K5M(akm2UAGFbtEYfxxOm4yvdI(wWv0mEaiJKN7Y01BKlTcIcOcDQMXDgco0Zt77kvWbQ2)CWWwLItxApwxa)UuNHTQKO8S094O4OZjRxKLywVvLki7LoQUBFIpF4L32ZLWSh1qdRkvswPNK(PwSah5rLnp(NafcN56nCTD4(qSVaQPYT6CCavQGLxdMeS9TlpgsL3u0mtlnYHPHlPT6Mwq6gba0ANudnTQugfePdOx6PiElsCFNiqTuODY5Bbg8Oq7Y4TOdXnZbhtEVoy8sXuAMQGupnGqQT3YTFPLbh1AFVAfroMg5KjBoGPgUNtJQZoepYLICOUPo0ThHLi(jbYI6ASugfXyiBjisjO7YYSOKmwqSuK41y06eIRmzuBfaBq8CYy6qLQjR6AR8pM5be)B4qDds1hM2h4urdrGmPI0PTAEZmTQKyjwXgto3XAFkmcTLNG90HucBMggL1hq5exBvymutJrguvtwFlQLzY6tgjuCqXs2nQ3LW994(b0K4S9kdy83iDRELegan0r7W66ip0Mb5B3KTTkY1(30jnsoqZGFVgJ0rPllRoe0zDXXQcIEyDngMY1ih5HJtk5K3H5Li5ib0G6wJedD1f8cCRY1l5gXPIvTuYO5Kt8ALp)3yiFq(nfjaTupbOfgKWdkJidthq4C2Y6CUQ10NcfxMeAPmZLe2ynqLWGqgqMSb1hkxYYQ(KbdwDamtWTErhazM8Q(saBRU1eoIhkIG08foRxMkH7fX8dsJNaQSbEb5KDINytaENMXgqJK30T5DW2kbJX6AmgbBCaYBOdj1iYeiNQJqo5sjhl9aNW5eGriJJnjGnvxd2KeOSdiNaAst0VhtHtyAsI4uXkfGcT(JdI7ZIdlySbluNEO9YC(4GkKGWU2ajQ7LICiHfmwJarVpVXeVygL3P4NuUyQeKEX8HfuN5W83otRqJ4WBTH0ziI8yz8Kt43VpCEElyS8nh)8gqZ15PauOvHDDIRCIUj5eQBAaqHJiC2uXhQjIxy5KllHb6e3zxQhnYjJ87emOkJqebH5PGAhU01PKaXTJ)jz2fJaVvgpxladHniNu6VWEY70LWW0UkfSiTUCi754XEE6d3pyYfLIM6Kn4sfRGh88gAm4nRQfEax(noyY9Gbkk9Ss1qFk1Gkujfs9Kn2kq)a39OHbSKmwRrdTvkMv1qUQism56WgX8CxwJnAOngYSQglj4mihsbhuGm1HLfU4YnAuhBB9E7MYBbzvUpkZ51rV)bA0qBgKzvnO0Bc7p5dOJc6E5g6Zoj06wtm2jJEZr1OHwxJzvRjCObgb(AyfTcowAKcSmEr)bQiYEk4B0OmsamlpwesLvfUmGddJtNbAtkmRQfBN9c3ADpvIKTdPZqoZljVKAGylzwfHlotG00HZz9HPZIQiJKoQa6WXKqeqx3kR9Z1SgoD5d9IGxwffsNc6Zmr6mOkowQo61ruRbkLlQd9knja1nA0aPXLlnUd(WXxzOmFAYs5AGuoTtDYRUjI9qzaPyGxpJC7W0OrDCzcpcfWlHPWi06UqfUsJy3c0v4uQCMOmDQkGo5DHe6eCXT84Nv4K7kiPORmDqjCUuuJnFx4QEZhCtp)bnSbceNzvTKen4wnHWDdruk)(TgidR2HwvIlktKsDacZDM4B0OooukLjnsri3sIjsE1Pq1qoDT4(LD8U0Xehc3yFVH3eMqhN9WR2aXQ1SQw9sA2KL9QAPbccSz1Y5p6J7sG3FbsVoueImJfuIuzRupAdyuE30TanskJAlWESou34u0UnlHSxAFb(c(2srLbuImydawVDsJ0gITNzveYfFEWL40iyjyvkxEVdrCH8280eusr0omRwfrj1dsCsWHBnE67kf7gM2nyn0WoS9X9yCjSTTaDYGyD)08yfQasyWJtogh2R55jFBQ5c3DHNIctGAGR4vQKZsQTqJAhj50HQGmnycX57rvoQMnePJiAhQhsf046DGp4D4kW1N0QUW1cC(GOG49ywvJqvIdNQRDxWruz(xNMgTnqGgnRwjjNeS9p9esSlasdyZImyzzcThIKSzvnuePxwQzYc11JD97pmToy3unpFAtsaZo)HMOH(SodDG27mz6u4NSVuLDYjiOvbZ4bnaLl7cV69a1nDij3nkq5sI5CJeEWq4ui41pwIqJxQK9e(OCHFtzk2niCYnt7(si1vJtEB)WJpwEO3UjBGeovzGwYhnceJuZQ1SM8fQLXE(NqsloUFtd8NerNUzpXcTbyVTh5oOcwuWzTEtK6wCszw4LcLjwF60gz4QL5qMFc1ZFq2lqMkMMAxvnRzIxhn4fIZ2UUE00q1QpM7vmR2OCMOiL2)T0H7sE2csBFCG0iBSNmAjtVgToPSHpYSCsfWBCAV(CQe47rJqLjI4A1gycxQcLfOcwb6BAQcDay6z6Kbzm1X4BlFoNbiGPGNEDq1int5lHC96qOHbjnVXZVyUrhAYvnDGzVMheztpz8azWLAE(OGv2cz)0H1sMlrxIWXlCpzGot8eZ0encSgEBHn61SBYalDAGggOJgMC2IbhFuiWmnlLqYZZANMg3zKnQbiWSMo(SB57YSjdLGwMjCYLt2aOJywsI3TswFannlH7RAum9cGXyfEmlnDDmXunOkgTzwyear)ozIcSzjKLshrs5gNSHL1LsZqimlIt7AJFl4UoyXKXU(P7lraDnRQJa0YU2CgrIKsAO5Ar7YPDtfJwmzdAP00gxU10Ec6pkHtZ6zoffHXA9nJQ9OiwADacBs6ltBaQdDGVmRHtaYnx04rCSnRwhJFG0ZtuwzMl3iOWiVKonsB6hD5MWvuLKaK58pNk6d30PJL4nWlynNmP6egWbZQyc6YCPxEDjqTsegP2ezwkMwHebW1ZHKQmAW76hh5KrZrjuZbEnBh66BdaNSHpxM5L735nODZmAs24RDbMdPis6ukHvPQwByhJwbC5BVHuQxYmQCg1vxwE5vkN)z9fXe9XPM2R0LdJ4dHRdiGUfRU3eZ8AkaQrdSg6t3f3VhnmuQ5m9uumitkbuQsYMveCBVH5IZjZZGyC104IBvlPtqmJb84YjpQowc0YG(WfJjpIfM2kA2(A4TgiCxVaiUb5lz2RgaOS612AyMIr8UKlz45DzVvXuFRuaTU2mtklmsNzzhedVdPhitQts6kHvnCLaVJbZ6rMerGl3gGy3o3HJaQisN0GIVR(SVVkNni03tAgsMHws3ynHlyJBqcJOUzLzLUqveHOxgjpWzgFP9bsdhYGDUPf60EnnaKQB9SxeYd(jjMiP4wJfzp9nXda3wMYJ6ZSW4OpuAOVE6M1YsRKYQXZDBVUeUhKfy0eWb2LM5gdfQdQpZkblmIN01(9v4rRYeJM5QtcfVrgJEvCtTcyEzY)v9rhhkRAm9IWPkGQKhsTJ7MX3(ejvMLsxjhKjeDMwOZx1W3Zfst9KytlZDm9QsUu61crfQwXXd8YQoeMNkF)j9PUU5Y0VsvswqXCqpUJkr6BZJP5tjmleaTAzp0DzWB30QoYoQdnZAdh50qc7NtyNgjr3sUCIjzT4efuQlnSxoL9wEGcKVhdgq4zSfa1HuYCuCS0xlGQ4mKHKxmXxk8LMcGdN8ssnB(AALapb(gyXBuJPYl8Wkb0e8TeskyJqwNNwWeNAMq0WuRJRsKiyLwJKHC(CaSPmZfvrRoVQ4YjkwknHJPYgXEqiOa4VsvdyLGGa(IuHZ8ujpHeUeP8IozT1UyI)FfRNfauTzfTC4uBBzgbMMyRwjaTG5KlK(06yit66WIYSHlPO6B(o6jSyq8IM26ouDzFNBhDcSpwzhtCyZvlsqGdKJL5RaQDvl1BNyV(5JNUzzuAAvDK2s4ebSgZuUet5W86hqVM03pKi3tdhMEWF90YNaEI(IkaooLd1Rgd77NA4bASEjn8eh4m0fczA6PjBpI(MQhIQxA9WKkbZaNSJOnCjNkRce8N0bvcYwj3AU2mLjrjBQIdpoT8OEw9KaU0Z13afaaOViFO6CiLjBs3HLHvfneSwPIznoL3NwaKXEP2oXVjXoBgxM52jf0RGcflLC1CWPEVj1TFb5vg7LN0RhJTYQSe92Twj8iKDIFx9lDJcPDla6aHY9hXrTYOnE10H2uPylZ91DBibIjHgBVDkYgjtADsIYIC4m)WcGZrEVjTdLin7yhAFsQz)LrBvRPPnWDgSAdxHrox3QBe5lVjvUvpTbqZWWdQcVRJmGrYedbJNZYEr(EmBsgScrb(LW3jlUxI5bbwPqYTImuZxkwf5mxDDXq00Sv6X)PKLwyF5k6moBxwyhQ2j4mhbHs6lEhOGjVTpiQBCyc)40svdlvY9eNxFQ024CcPlzP9rUCf89yaMPeTK338JMFaLS0AYlxPYiVCJwJDI(WCKkmPKLMtQCLkt8oWFlkJNuwTWIYvW0wdU0m6d(FNFjiPyOWFvMZNl6XL0xpsqpJjDODCxDs2VQFAmvlzzIRbvWl3fxa9v4s6EtwVmDCvSJX7V5t0UL2MZ6eNiOUKLgUXYv0Wn(fiCj7S0NJ9ZE4jYWoGbSRsPY1XEQ(yhN9nyGiU9YyyrjRsitH2FOdCiHWLTrVOjyNAj9vjguCf3X1auz7ttolMPddKRSETKayhPYeG8KKIi)wYzUlsFtaa3NsGHsz6DKUO9UC5a4fs3WGqQ8yfEsMWqxQCDSHXCF2hUfruMKgrdY0QiBPgIHu3bGBOnLBXnPHXConB(gxQCDSI6mnpj3NxrpdYiAVKvjKDw7q)buVyy1BKy)xQCdKdOE(lzojPX2OjTVuou2HIvjKpu77BAMsJ7k1fTCLAjJJK3woCUkqYz2(MwCSL1OTTP(eWEEfh3H1aNLqktWo)2VkUiQHbtNOPJxH3ErdB1LBqUxaHVQ69oi0iQNpHIO(euevHZ(6HfEdhUd4)Q8fzO6zDdpb(yyepeyBxy(xZB(cPVQh7671J1FPUHNSiwJEdIY9Yq84cgNK5vGyAlvy(cqZ)QwV(IPtivTF1tGr4XQb34nc0DyfU8Ln4u5fSGrxiyhHgDOrNsPEgFXy9RiBJbWBfcJou4DATHS3HyivWyazOHhLABe5N0iDqVW1ZFOnBf3bwvKp(KNVFyCNfsEJYEP5x4v)rk86ptb5)U48xQqYxL(IODXKNL9veVQLKRdZ)doFAzWxy6lMBC4gpWlmpTqUcMmax8TZuEGwUTTXvmI8H9wu(c6w4vvRWlTTSaV(IPYpz9WAL8MhoT98uVOJhPraJdF9rkzx4KunErxfE8OL1ZpAsTQF0yTAGB8eA0dCJZ0MaJYHfmy2aNctZVPMsfgzBG6PVEkFh(J(1WmUv4vz2VE(LJKcMTesM9SFlscXFIyEHuE0czRvbJVKEvf(vH0fo43fW1g4xfWPp8R3ECgf43z2hJ8DgmVn5(Xble7XI2En89PQK57AWJ8GOpme)A4nGQ6Xnjm7SpThXnKQFrRosxq0VZ1ximIR6aGk01H45rDle64FA622rLAq88YT(Z6ziRq6Rx2r4SuTkSeP(RrPCjf4kgZ3C5TxBE5rwfONBhQNv7S(HhSCZ2VYHRUC713C)MVYHBT)URV4KPXPD48Ykn)9Kg3I6zVQdjcE52q6lxrkOBHhCsgGMdWK2cEF7UGInnhH7lL0uY1QRyaVxTtL501rLWDJ(8e5b69djFHMfC1dHEDPnPrWVH91RmC71WbqM2XZMEtPyf4Ie2R)4Lq)ocESbqx1RV8C9Z2D99MC)8fJL3NnJvJxs98XR0BFUlNhiJYC2fuy)e8SVBSWcBtK7mHgCj5o5rxBvRulPFTdp)tfASWtfU48fYwj5RF40hPKfiFwMffTibSAGKHKVlrcH87GpnortZeS0sgZF55HFnXrDcbuUT)BBkOw4d0TAXqz6T8eTebd(QxH8G8u53V)bT3E)9AbJLjOlvrRPdcK8jazjNQG806Wu5qOq4Xe(hI6fmUY9yJyU(aB(mQC093yTE2Eaw8zy3C)yqppbo4mxjEEsLI1txOXeVf(QZp)RNSoN7BMe3)9BxWiC8Z)wD71RxpcHqK8zjeyMI77T4pVXM(GzxG7RDJdJ8hy4hae4qJish4B6tJmcJi8iQ9NnVG33EIZv924e2aQNwkN8989(hS(ERVwogPclT0sPlWx(YY343gNY8a)ICaSsr3ltO2gxXWQGXM0O9IhSJVVChq4cJrP1V0XzEhBCfO0qrB56hba2UaBXrvBjl4evaDE2Yb145haxqhlmYRM8LEM5xCXXnwjX0oqHyQriAU9j23Wp3GsoE5yojCPwDjQ9MHlm)nw(Ww7Vr7dBUERd3B)2BVXRmFbJjTdzImTz(CgLHksvR2l3S9HscwZ93zN8KldiZhZ2fajJfs9K0gBUFGCpEFPuhGwo39IE0eAm5cH3XlmAl)D66(3QR3FhSop2A4QBTC7d3T1MYLXrwbhe2F0LVOrx)66qIUVledc7RxhGfAiF5I50)aYcW41AKvHrBHScLN)Yk1FZF)1bO9lnv(FETl4K9CKoCmDywnYZF55xAjJJhrg9X0HFROK4bsCy2LNL3BV9V2ERU(OB0OexjnOW5mNZ4lE45m)6gZ555zs25i3XGRZloM4qDnbgNfqoVRGpnrVo8mpM7I3lbNhwiZMEP1kE98xq1slEo1jmIprt240qk)eQTrNHpVX8QgE824(XtO67xFI2gij5yVpI1ztSWOVQtW8QZxK(y9Y8pZ8tSGJk4EYv2y(5EqQ44Uj(aPpys8QtqZWy8RgZnkJatlQFeEHr5V1YT2b1iN3n0SZISShTAAaQtmEQW5t6OfFaLqT22T2D7wToVDGFRT17KLYBG2iFP20UZ3EXhiHg6r8HB3E9DNSKvJhut0pUWOtNj53p7CfJ8mlE5jiaHjfoKbllJX4hZVwmPVp)cz(sqNyDYzoUX9LjFm7ZFaucQx6NVamMw8BDsxRvxEVdxz5nBDo7FYq50cxs(k1qu3lz7yGo2H034kgMfkpgfe(2qx)iPLZRE4Q(EY8XLd(pM8H9IhaMhhUqhs)XzcMGDiNxdj3xVg0mfGo9BldHn(dewcNTLBVER23F5dx(Yg20oXYK(iPSfm89ChAiFxWk1DzmG4bVxKFoE8dcdh01AUTjytOeo6IfL5HBXIYWIuPcKL6wfRuVwQBAJHqBeDqghMLn14iXML4mbiwLoKDfRcdirolXjE2(dwWQq5jZ)mo(RqJwycU)oQNST8hq99OZx4CljIB7Q7SCRwh2A)MTpC)MRTEZxn)iZOXIV(53iAODwiBDw04h2WCPksw15B7WcnyHgezrNFrf4qJ1EV99gYGVfzJVh6W2D)12EJTxV5HTAVC71pC1TwEVnh1b7JPdlea3J1u7XLSagaFEYu0MqgXbSx3oe2FZ9DFr6q4eAVWIFlPd5KLG2bQiaCCe39btJ59v26BpxgGRGfRvi8vDzDpEd9cqyc8kjljeE)WmRehW6ECCai0s(nlLvYb0hYOgcxfiXb3Z25bwXHuN98fo3oBnw4a8cZ4B)odTutj4487TL1MtbHu(KVl1NsRdFW7yFx35EBXdFK4r(PfZCZzpM1lfRk4kXLUKgn0undkEtU8s024kPfNN(c0zeTvJ0IQNNl2Eq4qYwqDasyDgWYwoK7kBrNiNx2bAH(f6KA1Rg)C4GVYxyKbMgZDevCy688TOrT6Yzbrlm)(ERdNaT5lKqLgnSMYAOAAUXZyyUu9c91)UJ(3gwjKIZVF2bs1RS9JX9OJky0VGrNhSgEx)4qkikitJhsD7vOtK3ItWYtGdAIGK(QZROIsycYqqtedN9dJAFANipziQ2H2lAL4OiFV5pNym2Bcc)UhgPKWG8QAgixAVOvJ4UVUAd14MKK1rG7BlPBLjv(7VXoUH0mtD5Hf8)3DUZHU47otEzt9D0S3ZoPCsguQNT4HpIB7FyFx)tDe)Oo3f(JdvxJFRaoNCh5d6bVWEUlayPA1Y6dsF8HrddOV3gnxE31BT(oRVA79BEB53kFEhz53)ek3LmuCRGYW7BjoCfZ9AlBBVVx4RLiv912LAZiVwl5154RTc7ykKm)l53VV4dnJyoXhw8reFuXhRQ4HUU4pK4rfp2JiUG4XfFfXpM4IIVI4JVr2NErXJlEK35jfFOzNs8Jl(JkEhXFmXF8ze)jMr8ti(tk(jNr8tnJ4pL4pTWwC70Q9Nr2y)zNDkXFUze)0Zi(Zl(li(zeZiUOygXp7rI)IoI)sox4M)ep0fgo7uIN4lSXT657f1I9M0odO2S4bRerVzuqee2bttiSdxdcb7BXNBU99mc97fXPGQGckARmQdZtVzGppcc1WQTU(8gQ1lPXwbW5EqwOEm59xCxF57QkaFuDml64FtJoux)txsCX7AtdLIyy(EI36H)P520EW5B9HkEmDyXUHN0Xv(sr7JF7bWjEhUkxoAfW(Y3VvYidgdIl2K5fehXbHu0WUo3ooKUJSQoI36H)TVvx46BkiK6CBji3Thgq7eYge4sVRdZM2KcVkX4hj(6RaAoUTlBalckK4XfFJGpfi(hEfmziLckF9BXv8B3bgmT8J5DPZoLW8JFNW4o7RIgZvpr81Mr81xb2)l(g3bezzi11iUyNqkCtBk(aNoNqCJPHFH3vASY1cmGU6D1gti)qWhprNRCy0uHMwWfg5X(UURSNVhv8wZCI4R9WIVEt5EpX34Usjgyxl(MIpW5SPN6lC20tF20p0ztpZztp7zt)WQQ9iIV(TqjFIVXDLJ5N1q(P7tn)qIV(TtKBi(gVRQtFaQR4InLKK7ghsxvtLos8boI3AMFpX)bNvaoKaVL7cjVBOX8BT9MBbEwPmThsvHdVXYn3B792eYfizQluWy(93yJTxD9MZBqJ6Ue8Yx3)0qdjluGRoBNaVacLN4ZqAaHlpEm6Coiu8)Q4)nX)7hj(6fjEEI)pLmbxexVLN4innw87lP6I)VUApXxZr81xbgaIVXDGeM45KPiI4IDI8733LkNsB9c)xnL8NteFTJoB6pwWNEnFAiyuV86qH5zubCZufjMqXx)DZobHvv46w7gezIbkU4ztFrXhCu(w15SP)ypK4R3CZRT9oRj(gn3mM5ARlQZelkxVyj(g8971dETdmHIdp6JC20F0JKD4d)Bl(p4KSiDRUQJkFOAL6wRIFexCEMne)UIFpX)Db)SRa77nG00hRJrKdjYOlXZOd1GtKNtTH(XYeHjskRWNRo7AdiD5(lb3wgCQ0Do3qFdIrxFopKg4RsXsTOiMNuuZPuYXGLAQ1ZcGt8AbmgHuP8lWDkxFI9sIlk(Vx8wp8VO4Rfu7b0d)eiH0U5d0Z2qHdvZGoK(HkuCGRvrnk4HlbhMez)AZGeXfo10qkgdB195eotc6aXMkVJjLo4l(6CveEll(F8Jl(FYr8ncEmOFGB5Zq8IkqCrX)ZaX5)fqGxgYfSrs8jo69jXr(dirSU3Gzh5iUQ4V8v36f(vEm4Nfh)pMDkXFLRoZmZm7uIFURc)AgXNe(8mIN8Qpnx54x4vF6BfaxVz8OHVlKIdhEclK1XL2ukuZ5PpB6Nk4XdJ7Su5LaLmhIAEoB6l99dFP4ToB6l9F7hwwUlaLR0sDKYHpSlyG6ztFjOl36f(nN7k)hn1uh2SRdT7XvfKzoB6ln7u36ecxErC2r5OXtF20FUpLSTE0m9zslT1l878Zb)C04)XmNn9ZuTJS1dFMK2)SPF2ZMUq2pY1XlqqkaFS4Y7TwsNEhvO476BdtVNqmZnN(FFI)otWzNV9DXGt7dMMVcP7XaBTNnAnF)cDkyTOULHjFt0tloT)sHXDuFo8vl96Y1M5MJ1lB5(YYWcPmuen5s1ydi3C7iD2cdw1Rp4aN6WCPzAHNFtAulj((sEmjkmWODtAK(bxw)XTOG6HfwukfpFR)dFfdRSaAnAFN)Zx2WAeOp65fviK9M0c(XrYR(TRmYiCdFVOm(FL5lBP)sSjEoRLkInZIzZ9mGFrXxmJIljL3tYhxvX7P3oC20x6OZM(z2yE)G5)YxrvVlyE20p7kqUgj(uBC20p6gNn9N05SP)uoNn9fCoB6N4OZM(t)eNn9N9SP)mI)hckPs50cqYLvqMoOfGm9SaKeNZvUAJAvlSsm1RRlBaPWA8yMDHcI)p2q8)9mNn937JC20Fpp8ztp3hs89DK4t7i((ps8d4i(Rk(Rf8OkE220BgDTaBsevqfFgN7AlFTRneE8DEkyFDRi(t5f8zZ88dvXV5q93Q)O4Xd(boNcLwIVVjuI7ZxhGF9V2ehebhgXgqp0EOhzaRRtWp45xMa4YchEBGnJ4oo3Ph7MuBjN5x5JSciCk4r3GZEtJxkMyZjreJ2Tf)UpPy(ze)8IFbXpyjXN7iXt9PNs8xxjj8xCLDwFJ2ZZSd(ezSgDpF4ccgEdb26AIl90IfosS4rIN5ht8ShXFJy5lVRZMEfrbhXL7jw6jep3Cct5)Aj)3IY)TKJO8dj(Bk(f4A2pXljQi(BjQ2zL9B3E)Df1e1VR6Cii39F1zNc(VzEp1ZE5971lKgHF8vuF8tp17hoaUOapG7lFh55iAiEEXFBhXxv8ll(7OMu)DVI4VN4xrC3zNs83F2Pe)dMDkX)qrBX)iX)yX)KpU4h6nEcXff)HH)5F6jI)zI)5IRO76TEHF3GF(FNV5383x8dlEbXNF2PelpJyLJexuS67yiwB2PeRp7uIneBk26oBV3ER38qyXtST4QIxu1Z78Jk2vSNy)NsCG4LenfFurlrBX1WPM46ZiUXNEkXl38PaBUd(mYTyr3lMXV)XkI3HKoD40tanUobF2753F4aYnFSGp3ekthw)dvHut)SGhB5KQTN8lcd(KtOIsLrhf8Kt4RUNdAiMfdoeM2n9Gx(ftCKpcdEWNE8YaE(IDK4xv8RjE3HI)LZoL4xFgXREK41eVU4IIFK35jYtUe)sbxq2keVUo(CnV1tnkP7SPxwS)tkoaSQxs8aU8js98JONnDlXJpPrOFuMryMX0Ni)y6SPx5SPF5DM6Epi(LeTe)stym05zFkqYRCqC20FHjosGcKzK4GJeX)kXVH4WV3tExXrFSNwqENh9SPFgbvmtW)ImO3tttqowVmwsUDO2VH9dOJJjJgR8rtPZL0PYz20UdrjH1ZyPLwkRM77xR9Q0xF0gsLD6FGszW11gvfgClf2D6WR8LaKrGO6OcG)8fE7cZLlLxtkqhFF351FBAMSQES6PzIQq2hRZd35vBTMVWCVT4F9DLg)eR0o1r0vyFblbTZwu4iYj(Tc(TZNZwztyXjKmttmbEgnZ5Mukgmwmfp3O6Fob3zYHs(CHHx0FoHZCcM4nehlCLy54j(eIbcFXx8ibFor4xDkr0D30JF1EfxiS6PxxCI4uHWr8V15oXH02((GVUhjg(iI3u8LeV1x5JCRt952WvlS41fV9Stj(YZoL4pYwVW)L)wWp)BUG970qmDvXdnN47zoXJmxtIlRVhSfwJHfN4XgqIOhjbZAmyRMaqwJ(KBt4DvqY8vEcXtm37bhxii15ukWKg6RD2SJYlaN3x97v0fm4rxXL9MVjC5SPNF3vvGSQaNDQ7OE4629PNn9dRlY2EG(W3v9bLeSpKUGGhjp8DGB5mkhG8z(DAEx1HLPfapWmINCoXNAU3Vl8IqN4fTbPBKpVtZLxB7R1sB1pCp0DZh6)6ejaE0tpaELPdB1lyaifDcvB8D2tM0jk8hUIr5mp0bFOrLmp9MfgkttaZ5YK)0zstQ89Xihne(sQ86aY2MeuJoxiKZo4FvzMw)LUzHH5JGmKs8304zn4A3zw6uWkkJNvp6NBIq8M9aC8D4Sabi774jHzUNaRXdnUSXcjZlhQghlnT6znQS43vNqF5ZHSaogLTaFxzgFFNF3JtBd8dGWXZDn48JEkClAaqSSARRlH6n0qFGsv5krkWXI5N5o9IDDv3mGhDR(CMTCBwZ1Un83s7V)WkyzHJeXN8H(W)ER0N7FANvVwR27VBh4V33tJ5GnyU9JpbZTZAQDtj8TF47Hb2a8WhkZ(aWq7oWBZS4WVYhru5D1Eriho3IRpgKZo1T4(NQeh0meoiPZiQYBV)bsByRjQVsOpps84Fa8RTg2bMIGs0ne)nCe)7CepTZztVQ0A7MYL5hMhgjVfRNDkXp0CAZj(upTG8Jl1XrpBAYOAaAckYlk1aWNteD3flUZPdDEPdE56BcI(VfG3nmRDqr(V9w)Qb)u)Sgtn1Nv8L36Zp8l(B(cFZV5x7cdUG9fcBwzPklv9cN8V7LHs()da
]]

-- Strip the leading/trailing whitespace from the heredoc
SOFT_RES_STRING = SOFT_RES_STRING:match("^%s*(.-)%s*$")

-- ============================================================
-- Bootstrap libraries
-- ============================================================

-- Determine the directory this script lives in so we can find Libs/
local script_path = (arg and arg[0]) or debug.getinfo(1, "S").source:match("^@?(.*)$")
local ROOT = script_path:match("^(.*[/\\])") or "./"

-- Compat shim: WoW exposes Lua stdlib aliases as globals, and some Lua 5.1
-- math functions were removed in 5.3+. LibStub/LibDeflate/LibSerialize
-- depend on these when running outside WoW. No Libs/* files are touched.
if not strmatch      then _G.strmatch      = string.match end
if not tinsert       then _G.tinsert       = table.insert end
if not tremove       then _G.tremove       = table.remove end
if not tsort         then _G.tsort         = table.sort end
if not tconcat       then _G.tconcat       = table.concat end
if not unpack         then _G.unpack         = table.unpack end
if not math.ldexp    then math.ldexp        = function(m, e) return m * 2.0 ^ e end end
if not math.frexp    then math.frexp        = function(x)
    if x == 0 then return 0, 0 end
    local e = 0
    local abs = x < 0 and -x or x
    while abs >= 1 do abs = abs / 2; e = e + 1 end
    while abs < 0.5 do abs = abs * 2; e = e - 1 end
    return x < 0 and -abs or abs, e
end end

dofile(ROOT .. "Libs/LibStub/LibStub.lua")     -- creates global LibStub
dofile(ROOT .. "Libs/LibDeflate/LibDeflate.lua") -- registers with LibStub
dofile(ROOT .. "Libs/LibSerialize/LibSerialize.lua") -- same

local LibDeflate   = LibStub("LibDeflate")
local LibSerialize = LibStub("LibSerialize")

-- ============================================================
-- Decode pipeline (from Transmission.lua:StringToTable)
-- ============================================================

local function decode(importString)
    if type(importString) ~= "string" or importString == "" then
        return nil, "Invalid input: expected non-empty string"
    end

    local _, _, encodeVersion, encoded = importString:find("^(!WA:%d+!)(.+)$")
    if not encodeVersion then
        encoded, encodeVersion = importString:gsub("^%!", "")
        if encodeVersion == 0 then
            return nil, "Missing !WA:N! prefix"
        end
    else
        encodeVersion = tonumber(encodeVersion:match("%d+"))
    end

    if encodeVersion < 2 then
        return nil, "Only version 2+ (!WA:2!) is supported"
    end

    local decoded = LibDeflate:DecodeForPrint(encoded)
    if not decoded then
        return nil, "LibDeflate:DecodeForPrint failed"
    end

    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then
        return nil, "LibDeflate:DecompressDeflate failed"
    end

    local success, deserialized = LibSerialize:Deserialize(decompressed)
    if not success then
        return nil, "LibSerialize:Deserialize failed: " .. tostring(deserialized)
    end

    return deserialized
end

-- ============================================================
-- Table printer (generic, no WoW deps)
-- ============================================================

local function printTable(t, depth)
    depth = depth or 0
    local indent = string.rep("  ", depth)
    local function kv(k)
        if type(k) == "string" then return string.format("[%q]", k)
        elseif type(k) == "number" then return string.format("[%d]", k)
        else return tostring(k) end
    end
    for k, v in pairs(t) do
        local line = indent .. kv(k) .. " = "
        if type(v) == "table" then
            print(line .. "{")
            printTable(v, depth + 1)
            print(indent .. "}")
        elseif type(v) == "string" then
            local display = #v > 200 and v:sub(1, 200) .. "..." or v
            print(line .. string.format("%q", display))
        else
            print(line .. tostring(v))
        end
    end
end

local function printStructure(data, label)
    print("")
    print("========================================")
    print("  " .. label)
    print("========================================")
    print("Type: " .. type(data))
    if type(data) == "table" then
        local keys = {}
        for k in pairs(data) do table.insert(keys, type(k) == "string" and k or tostring(k)) end
        table.sort(keys)
        print("Keys (" .. #keys .. "): " .. table.concat(keys, ", "))
        print("")
        printTable(data, 0)
    else
        print(tostring(data))
    end
    print("========================================")
    print("")
end

-- ============================================================
-- Main
-- ============================================================

if SOFT_RES_STRING == "" or SOFT_RES_STRING:find("PASTE_YOUR_STRING") then
    print("")
    print("=== EDIT SoftRes_test.lua ===")
    print("Set SOFT_RES_STRING to your softres.it export string.")
    local script_name = arg and arg[0] or "SoftRes_test.lua"
    print("Then run: lua " .. script_name)
    print("")
    os.exit(1)
end

local ok, data_or_err, err_msg = pcall(decode, SOFT_RES_STRING)
if not ok then
    print("DECODE CRASHED: " .. tostring(data_or_err))
    os.exit(1)
end

if data_or_err == nil then
    print("DECODE FAILED: " .. tostring(err_msg or "unknown error"))
    os.exit(1)
end

printStructure(data_or_err, "Top-Level Decoded Data")
