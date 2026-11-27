* ============================================================================
* Trabalho de Econometria: inflacao por faixa de renda no Brasil 2020 a 2026
* Etapa 1: importar a base, criar a data mensal e calcular o gap 
* ============================================================================

clear all
set more off

* A folha contem cabecalhos na linha 1 e dados nas linhas 2 a 83.
* A coluna DATA e um indice de 1 a 82, nao uma data de calendario.
import excel using "/Users/luisabsoares/stata/stata-database.xlsx", ///
sheet("Mensal (2)") cellrange(A1:C83) firstrow case(lower) clear

* Conferir o import antes de transformar os dados
describe
list in 1/5

* Renomear as vals com os nomes correspondentes
rename data ordem
rename p infl_baixa
rename r infl_alta

* Conferir a estrutura esperada: 82 meses, em sequencia e sem valores em falta
assert _N == 82
assert ordem == _n
assert !missing(infl_baixa, infl_alta)

* Criar a data mensal: obs 1 = janeiro de 2020
generate mdate = ym(2020, 1) + ordem - 1
format mdate %tm
label variable mdate "month"

* As taxas estao em percentual; a diferenca fica em pontos p.p.
label variable infl_baixa "inflacao mensal: renda muito baixa (%)"
label variable infl_alta  "inflacao mensal: renda alta (%)"
generate gap_pp = infl_baixa - infl_alta
label variable gap_pp "inflacao renda muito baixa menos renda alta (p.p.)"
format infl_baixa infl_alta gap_pp %9.3f

* Declarar dados temporais e verificar unicidade
isid mdate
tsset mdate, monthly

* Resumo e primeiras obs para Conferir, pg 05 - tabela 02
summarize infl_baixa infl_alta gap_pp
list mdate infl_baixa infl_alta gap_pp in 1/6

* graph 1: comparar as duas taxas mensais
* apendice A, figura 3
twoway (line infl_baixa mdate, lcolor(navy) lwidth(medthick)) ///
       (line infl_alta mdate, lcolor(maroon) lwidth(medthick)), ///
       title("Inflação mensal por faixa de renda") ///
       subtitle("Brasil, janeiro de 2020 a outubro de 2026") ///
       ytitle("Inflação mensal (%)") ///
       xtitle("Mês") ///
       legend(order(1 "Renda muito baixa" 2 "Renda alta") rows(1)) ///
       name(g_inflacao_faixas, replace)

* graph 2: gap entre as taxas em cada mes, pg 06 - figura 01
* Gap positivo: inflacao maior para renda muito baixa.
* Gap negativo: inflacao maior para renda alta.
twoway (line gap_pp mdate, lcolor(navy) lwidth(medthick)), ///
       yline(0, lcolor(gs8) lpattern(dash)) ///
       title("Diferença mensal entre faixas de renda") ///
       subtitle("Renda muito baixa menos renda alta") ///
       ytitle("Diferença (pontos percentuais)") ///
       xtitle("Mês") ///
       name(g_gap_inflacao, replace)

* ============================================================================
* Etapa 2: verificar a persistencia e testar estacionariedade do gap
* Somente execute este bloco depois de criar gap_pp e declarar a tsset.
* ============================================================================

* Estat descritivas: media, dispersao, extremos e percentis
summarize gap_pp, detail

* Correlograma: autocorrelacoes, autocorrelacoes parciais e teste Q
corrgram gap_pp, lags(12)
ac gap_pp, lags(12) name(ac_gap, replace)
* Apendice A, figura 4
pac gap_pp, lags(12) name(pac_gap, replace)
* Apendice A, figura 5

* Testes ADF conforme executados na analise (sem drift): H0 = raiz unitaria.
* Comparamos 1 e 3 defasagens como analise de sensibilidade.
* Pg 07 - tabela 03
dfuller gap_pp, lags(1)
dfuller gap_pp, lags(3)

* Teste Phillips-Perron: H0 = a serie tem raiz unitaria
* A opcao lags(3) define a largura usada na correcao Newey-West.
* Pg 07 - tabela 03
pperron gap_pp, lags(3)

* ============================================================================
* Etapa 3: comparar a persistencia com modelos parcimoniosos
* Usamos a mesma amostra nos 3 modelos para comparar AIC/BIC.
* A amostra inicia em marco de 2020 para que L2 esteja compativel.
* ============================================================================

* Modelo de ref: o gap oscila em torno de uma media constante
* Pg 07 - Tabela 04
regress gap_pp if mdate >= ym(2020, 3)
estimates store media
estat ic

* AR(1): o gap deste mes depende do gap do mes anterior
* Pg 07 - Tabela 04
regress gap_pp L.gap_pp if mdate >= ym(2020, 3)
estimates store ar1
estat ic

* AR(2): acrescenta o gap de dois meses anteriores
* Pg 07 - Tabela 04
regress gap_pp L(1/2).gap_pp if mdate >= ym(2020, 3)
estimates store ar2
estat ic

* No modelo AR(2), testar se a segunda defasagem acrescenta info
test L2.gap_pp

* ============================================================================
* Etapa 4: diagnosticar variancia constante nos residuos do AR(1)
* Primeiro, verificar autocorrelacao dos residuos dos modelos candidatos.
* ============================================================================

* Modelo de media constante
estimates restore media
predict resid_media, residuals
corrgram resid_media, lags(12)
wntestq resid_media, lags(12)

* Modelo AR(1)
estimates restore ar1
predict resid_ar1, residuals
corrgram resid_ar1, lags(12)
wntestq resid_ar1, lags(12)
* Pg 07 - Tabela 05

* Inspecao grafica dos residuos AR(1)
* Pg 08 - Figura 02
* Apendice A - Figura 06
tsline resid_ar1, yline(0) title("Resíduos do modelo AR(1)") ///
       name(g_resid_ar1_tempo, replace)
rvfplot, yline(0) title("Resíduos versus valores ajustados: AR(1)") ///
       name(g_resid_ar1_ajustados, replace)

* H0 dos testes seguintes: variancia constante / ausencia de heterocedasticidade.
* Breusch-Pagan/Cook-Weisberg, sem exigir normalidade dos erros
* Pg 07 - Tabela 05
estat hettest, iid

* Teste geral de White para heterocedasticidade
* Pg 07 - Tabela 05
estat imtest, white

* ARCH-LM: verifica se a variancia depende de choques passados
* Pg 07 - Tabela 05
estat archlm, lags(1/4)

* ============================================================================
* Etapa 5: testar efeitos sazonais controlando pela dinamica AR(1)
* Janeiro como referencia; o teste conjunto avalia os outros meses.
* ============================================================================

generate mes = month(dofm(mdate))
label variable mes "Mes do ano"
* Pg 07 - Tabela 04
regress gap_pp L.gap_pp i.mes if mdate >= ym(2020, 3)
estimates store ar1_mes
testparm i.mes
estat ic

*fim
