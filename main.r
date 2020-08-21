trace(grDevices::png, quote({
  if (missing(type) && missing(antialias)) {
    type <- "cairo-png"
    antialias <- "subpixel"
  }
}), print = FALSE)


library(dplyr)
library(ggplot2)
library(knitr)
library(kableExtra)


# Importar arquivos
item_contrato <- data.table::fread("info_item_contrato_novo.csv", encoding="UTF-8", colClasses=c("id_orgao"="character"))
info_contrato <- data.table::fread("info_contrato.csv", encoding="UTF-8", colClasses=c("id_orgao"="character"))
item_licitacao <- data.table::fread("info_item_licitacao.csv", encoding="UTF-8", colClasses=c("id_orgao"="character"))
orgaos <- data.table::fread("d8ag0132l0g7r7_public_orgao.csv", encoding="UTF-8", colClasses=c("id_orgao"="character", "cd_municipio_ibge" = "character"))
casos <- data.table::fread("HIST_PAINEL_COVIDBR_13ago2020.csv", colClasses = c("codmun" = "character"))
ibge <- data.table::fread("IBGE.csv", encoding="UTF-8", colClasses=c("Código do Município"="character"))
pop <- data.table::fread("populacao.csv", encoding="UTF-8", colClasses=c("Cód."="character"))
empenho <- data.table::fread("info_empenhos.csv", encoding="UTF-8", colClasses=c("id_orgao"="character","cnpj_cpf"="character"))
similares <- data.table::fread("itens_similares_covid.csv", encoding="UTF-8")


# Limpar variáveis
ibge <- janitor::clean_names(ibge)
casos <- janitor::clean_names(casos)
pop <- janitor::clean_names(pop)
casos <- janitor::clean_names(casos)

# Filtrar apenas valores máximos de casos e óbitos
max_casos <- casos %>% group_by(codmun) %>% top_n(1, casos_acumulado)

# Filtrar apenas dados de 2017 do IBGE
ibge <- filter(ibge, ano == 2017)
ibge <- mutate(ibge, cod_sem_ver = substr(codigo_do_municipio, 1,6))


# Código Manoel para identificar serviços
servicos <- item_contrato %>%
  mutate(ds_item = tolower(iconv(ds_item , from="UTF-8", to="ASCII//TRANSLIT"))) %>%
  filter(stringr::str_detect(ds_item, "(contratacao de empresa)|(prestacao de servico[s]?)|^servico[s]?|(a prestacao de)|(contratacao de prestacao)|(contratacao de servico)|(aluguel/loca)|servia|(contratacao contratacao de)|(contratacao da empresa)|(contratacao de)|(repasse hospital)|(empenho global)|(locacao de infraestrutura)|(fornecimento de alimentacao)|(fornecimento de gestao)|(contratacao emergencial gerenciamento)|(gerenciamento, operacionalizacao)|(reforma do predio)|(execucao de obras)|(contratacao, de servicos)")) %>%
  mutate(flag_servico = 1)

# Remédios
remedios <- item_contrato %>%
  mutate(ds_item = tolower(iconv(ds_item , from="UTF-8", to="ASCII//TRANSLIT"))) %>%
  filter(stringr::str_detect(ds_item, "cloroquina|ivermectina|azitromicina")) %>%
  mutate(flag_remedio = 1)

# Somar licitações efetivadas
cont_licit_efetivadas <- item_contrato %>%
  left_join(select(orgaos,!(home_page) ), by="id_orgao") %>%
  group_by(cd_municipio_ibge, id_licitacao) %>%
  summarize(lic_concluidas=n()) %>%
  group_by(cd_municipio_ibge) %>%
  summarize(lic_concluidas=n())

# Somar dados por fornecedor
fornecedores_mun <- empenho %>%
  mutate(vl_liquidacao = tidyr::replace_na(vl_liquidacao, 0)) %>%
  left_join(select(orgaos,!(home_page) ), by="id_orgao") %>%
  group_by(cd_municipio_ibge, nm_credor, cnpj_cpf, id_licitacao, nome_municipio) %>%
  summarize(lic_concluidas=n(), vl_liquidacao = sum(vl_liquidacao)) %>%
  group_by(cd_municipio_ibge, nome_municipio, cnpj_cpf, nm_credor) %>%
  summarize(lic_concluidas=sum(lic_concluidas), vl_liquidacao = sum(vl_liquidacao))

fornecedores <- fornecedores_mun %>%
  group_by(cnpj_cpf, nm_credor) %>%
  summarize(lic_concluidas=sum(lic_concluidas), municipios_contratantes=n(), vl_liquidacao = sum(vl_liquidacao))

# Associar itens a cod_mun
item_contrato <- left_join(item_contrato, select(orgaos,!(home_page) ), by="id_orgao") %>%
  left_join(select(servicos,id_licitacao,flag_servico), by = c("id_licitacao")) %>%
  mutate(flag_servico = tidyr::replace_na(flag_servico, 0))

# Somar valores não-serviços
soma_mun_item_contr_filtrados <- item_contrato %>%
  filter(flag_servico == 0) %>%
  group_by(cd_municipio_ibge) %>% 
  summarise(soma_vl_item_contrato_objetos = sum(vl_item_contrato), soma_vl_item_contrato_objetos = sum(vl_item_contrato), soma_qt_itens_contrato_objetos = sum(qt_itens_contrato)) %>%
  unique()

# Somar valores remédios
soma_remedios <- remedios %>%
  group_by(cd_municipio_ibge, nome_municipio) %>% 
  summarise(soma_vl_tota_item_contrato_objetos = sum(vl_total_item_contrato), soma_qt_itens_contrato_objetos = sum(qt_itens_contrato)) %>%
  unique()

# Somar valores contratados todos
soma_mun_item_contr <- item_contrato %>%
  group_by(cd_municipio_ibge) %>% 
  summarise(soma_vl_item_contrato = sum(vl_item_contrato), soma_vl_item_contrato = sum(vl_item_contrato), soma_qt_itens_contrato = sum(qt_itens_contrato)) %>%
  left_join(select(ibge,"codigo_do_municipio","nome_do_municipio","impostos_liquidos_de_subsidi","produto_interno_bruto_a_prec","produto_interno_bruto_per_cap","cod_sem_ver"), by= c("cd_municipio_ibge" = "codigo_do_municipio")) %>%
  left_join(select(pop, "cod", "x2019"), by= c("cd_municipio_ibge" = "cod")) %>%
  left_join(select(max_casos, codmun, casos_acumulado, obitos_acumulado), by= c("cod_sem_ver" = "codmun")) %>%
  left_join(cont_licit_efetivadas, by = c("cd_municipio_ibge")) %>%
  left_join(soma_mun_item_contr_filtrados, by = c("cd_municipio_ibge")) %>%
  unique()

# Calculcar variáveis proporcionais
soma_mun_item_contr <- soma_mun_item_contr %>%
  mutate(valor_sobre_pib = soma_vl_item_contrato/produto_interno_bruto_a_prec) %>%
  mutate(valor_sobre_pop = soma_vl_item_contrato/x2019) %>%
  mutate(valor_sobre_casos = soma_vl_item_contrato/casos_acumulado) %>%
  mutate(valor_sobre_obitos = soma_vl_item_contrato/obitos_acumulado) %>%
  mutate(casos_sobre_hab = casos_acumulado/x2019) %>%
  mutate(obitos_sobre_hab = obitos_acumulado/x2019)


# Filtrar os 24 municípios com valores zerados pagos
soma_mun_item_contr <- filter(soma_mun_item_contr, soma_vl_item_contrato != 0)

# Exportar 10 maiores valores
head(arrange(select(soma_mun_item_contr,nome_do_municipio, soma_vl_item_contrato, valor_sobre_pop, valor_sobre_casos, lic_concluidas),desc(soma_vl_item_contrato)), n = 10) %>%
  kable(align="l", format.args = list(big.mark = ","), digits=2) %>%
  kable_styling(bootstrap_options = c("striped"), position = "center")

# Exportar 10 maiores contratantes
head(arrange(select(soma_mun_item_contr,nome_do_municipio, soma_vl_item_contrato, valor_sobre_pop, valor_sobre_casos, lic_concluidas),desc(lic_concluidas)), n = 10) %>%
  kable(align="l", format.args = list(big.mark = ","), digits=2) %>%
  kable_styling(bootstrap_options = c("striped"), position = "center")

# Exportar 10 maiores fornecedores geral
head(arrange(fornecedores,desc(lic_concluidas)), n = 10) %>%
  kable(align="l", format.args = list(big.mark = ","), digits=2) %>%
  kable_styling(bootstrap_options = c("striped"), position = "center")

# Exportar 10 maiores fornecedores por valor
head(arrange(fornecedores,desc(vl_liquidacao)), n = 20) %>%
  kable(align="l", format.args = list(big.mark = ","), digits=2) %>%
  kable_styling(bootstrap_options = c("striped"), position = "center")

# Exportar 10 maiores fornecedores por municipio
head(arrange(fornecedores,desc(municipios_contratantes)), n = 10) %>%
  kable(align="l", format.args = list(big.mark = ","), digits=2) %>%
  kable_styling(bootstrap_options = c("striped"), position = "center")

# Itens mais caros
item_contrato %>%
  filter(flag_servico == 0) %>%
  arrange(desc(vl_item_contrato)) %>%
  select(nome_municipio, vl_item_contrato, qt_itens_contrato, ds_3, ds_item) %>%
  head(n = 30) %>%
  kable(align="l", format.args = list(big.mark = ","), digits=2) %>%
  kable_styling(bootstrap_options = c("striped"), position = "center")

# Regressão valor_sobre_pop casos_sobre_hab
ggplot(soma_mun_item_contr, aes(valor_sobre_pop, produto_interno_bruto_per_cap)) +
  geom_point(aes(colour = log(casos_sobre_hab))) +
  scale_colour_gradientn(colours = terrain.colors(10)) +
  geom_smooth(method = "lm", se= FALSE)

# Regressão #2 valor casos
ggplot(soma_mun_item_contr, aes(log(soma_vl_item_contrato_objetos), log(produto_interno_bruto_a_prec))) +
  geom_point(aes(colour = log(casos_acumulado))) +
  scale_colour_gradientn(colours = terrain.colors(10)) +
  geom_smooth(method = "lm", se= FALSE)

# Municípios com mais casos
soma_mun_item_contr %>%
  mutate(casos_sobre_hab = casos_sobre_hab*1000) %>%
  unique(nome_do_municipio) %>%
  arrange(desc(casos_sobre_hab)) %>%
  select(nome_do_municipio, casos_sobre_hab, casos_acumulado) %>%
  head(n = 20) %>%
  kable(align="l", format.args = list(big.mark = ","), digits=2) %>%
  kable_styling(bootstrap_options = c("striped"), position = "center")  

# Municípios com mais óbitos
soma_mun_item_contr %>%
  mutate(obitos_sobre_hab = obitos_sobre_hab*1000) %>%
  unique() %>%
  arrange(desc(obitos_sobre_hab)) %>%
  select(nome_do_municipio, obitos_sobre_hab, obitos_acumulado) %>%
  head(n = 20) %>%
  kable(align="l", format.args = list(big.mark = ","), digits=2) %>%
  kable_styling(bootstrap_options = c("striped"), position = "center") 


head(arrange(select(soma_mun_item_contr,nome_do_municipio, soma_vl_item_contrato, valor_sobre_pop, valor_sobre_casos, lic_concluidas),desc(lic_concluidas)), n = 10) %>%
  kable(align="l", format.args = list(big.mark = ","), digits=2) %>%
  kable_styling(bootstrap_options = c("striped"), position = "center")

# Maiores gastos com remédios
head(arrange(soma_remedios,desc(soma_vl_tota_item_contrato_objetos)), n = 10) %>%
  kable(align="l", format.args = list(big.mark = ","), digits=2) %>%
  kable_styling(bootstrap_options = c("striped"), position = "center")


# Summaries
n_distinct(item_contrato$cd_municipio_ibge)
n_distinct(item_contrato$id_licitacao)
sum(item_contrato$vl_item_contrato)
n_distinct(empenho$cnpj_cpf)

# Filtrar similares
similares_filtrado <- similares %>%
  filter(similaridade >= 0.6 & vl_item_pesq != 0)

# Criar novas variáveis similares
similares_filtrado <- similares_filtrado %>%
  mutate(dif_preco = (vl_item_pesq-mediana_no_estado)/mediana_no_estado)

# Filtrar maiores discrepâncias
head(arrange(similares_filtrado,desc(dif_preco)), n = 50) %>%
  kable(align="l", format.args = list(big.mark = ","), digits=2) %>%
  kable_styling(bootstrap_options = c("striped"), position = "center")
