#!/usr/bin/env Rscript

"> 02_plot_fig3.R <

Plot the multi-panel fig (bunch of barplots & a centrepiece doughnut chart).
" -> doc

setwd('~/csiro/beck/biofeedback_ir/')

suppressPackageStartupMessages({
  library(cowplot)
  library(forcats)
  library(dplyr)
  library(ggplot2)
  library(readxl)
  library(scales)
  library(stringr)
  library(tidyr)
})

# one-stop shop to modify colour across all plots. current colours are from
# BrBG (Brewer) hex codes
COLOR_YES <- '#018571'
COLOR_NO  <- '#dfc27d'

# other constants
XLSX_FILENAME <- './Supplementary Tables (S1-4).xlsx'

# for these plots, we exclusively focus on the studies that are either
# Effective?: Yes or No; we exclude "All groups improved" and "NA" ("NA" stems
# from the linebreaks that subgroup papers by originating review paper
#
# TL;DR: we're scraping numbers off Table S3 (sheet=3) from the xlsx

# plot centrepiece: a doughnut chart that plots # of Yes vs. No
doughnut_tib <- read_excel(XLSX_FILENAME, sheet=3, range='B6:C7') |>
  pivot_longer(cols=c(Effective, `Not effective`), names_to='Effective?', values_to='n') |>
  # ugly code, but the "factor" bit guarantees that, even if rows are swapped,
  # the ordering is preserved
  mutate(`Effective?`=factor(`Effective?`, levels=c('Not effective', 'Effective')))

g1 <- ggplot(data=doughnut_tib, aes(x='', y=n, fill=`Effective?`)) +
  geom_bar(stat='identity', color='white') +
  geom_text(aes(x=2, label=paste0(`Effective?`, '\n', n)),
            position=position_stack(vjust=0.5), size=6) +
  scale_fill_manual(values=c('Effective'=COLOR_YES, 'Not effective'=COLOR_NO)) +
  coord_radial(theta='y', start=-.75*pi, end=.75*pi, inner.radius=0.5) +
  theme_void(12) +
  theme(legend.position='none')
g1

# next four plots are for
# - behaviours
# - number of behaviours
# - biomarkers
# - number of biomarkers

# plot top-left subpanel (behaviours)
behaviour_tib <-
  read_excel(XLSX_FILENAME, sheet=3, range='A12:C19',
             col_names=c('Behaviour', 'Yes', 'No')) |>
  mutate(Behaviour=str_replace_all(Behaviour, '/', ' / ')) |>
  # sort bars by stacked length (Yes + No)
  group_by(Behaviour) |> mutate(n=sum(Yes, No)) |> arrange(-n) |> select(-n) |>
  pivot_longer(cols=c(Yes, No), names_to='Effective?', values_to='n')

g2 <- ggplot(data=behaviour_tib, aes(x=n, y=fct_rev(fct_inorder(Behaviour)), fill=`Effective?`)) +
  geom_bar(position='stack', stat='identity') +
  geom_label(data=behaviour_tib |> filter(n > 0), aes(label=n), size=4, hjust=1,
             position=position_stack(vjust=0.95), fontface='bold',
             fill='white', label.size=0) +
  scale_fill_manual(values=c('Yes'=COLOR_YES, 'No'=COLOR_NO)) +
  scale_x_continuous(position='top') +
  scale_y_discrete(labels=label_wrap(18)) +
  labs(x='Number of studies', y='Behaviour') +
  theme_minimal(16) +
  theme(legend.position='none',
        axis.text.x=element_blank(),
        panel.grid=element_blank())
g2

# plot top-right subpanel (number of target behaviours)
behavnum_tib <-
  read_excel(XLSX_FILENAME, sheet=3, range='A21:C24',
             col_names=c('Number of behaviours', 'Yes', 'No')) |>
  pivot_longer(cols=c(Yes, No), names_to='Effective?', values_to='n')

g3 <- ggplot(data=behavnum_tib, aes(x=n, y=forcats::fct_rev(forcats::fct_inorder(`Number of behaviours`)), fill=`Effective?`)) +
  geom_bar(position='stack', stat='identity') +
  geom_label(data=behavnum_tib |> filter(n > 0), aes(label=n), size=4, hjust=0,
             position=position_stack(vjust=0.05), fontface='bold',
             fill='white', label.size=0) +
  scale_fill_manual(values=c('Yes'=COLOR_YES, 'No'=COLOR_NO)) +
  scale_x_continuous(trans=scales::reverse_trans(), position='top') +
  scale_y_discrete(position='right') +
  labs(x='Number of studies', y='Number of behaviours') +
  theme_minimal(16) +
  theme(legend.position='none',
        axis.text.x=element_blank(),
        panel.grid=element_blank())
g3

# plot bottom-left subpanel (biomarkers, grouped)
biomarkers_tib <-
  read_excel(XLSX_FILENAME, sheet=3, range='L27:N31',
             col_names=c('Type of biofeedback', 'Yes', 'No')) |>
  mutate(`Type of biofeedback`=str_replace_all(`Type of biofeedback`, '/', ' / ')) |>
  # sort bars by stacked length (Yes + No)
  group_by(`Type of biofeedback`) |> mutate(n=sum(Yes, No)) |> arrange(-n) |> select(-n) |>
  pivot_longer(cols=c(Yes, No), names_to='Effective?', values_to='n')

g4 <- ggplot(data=biomarkers_tib, aes(x=n, y=fct_inorder(`Type of biofeedback`), fill=`Effective?`)) +
  geom_bar(position='stack', stat='identity') +
  geom_label(data=biomarkers_tib |> filter(n > 0), aes(label=n), size=4, hjust=1,
             position=position_stack(vjust=0.95), fontface='bold',
             fill='white', label.size=0) +
  scale_fill_manual(values=c('Yes'=COLOR_YES, 'No'=COLOR_NO)) +
  scale_y_discrete(labels=label_wrap(18)) +
  labs(x='Number of studies', y='Type of biofeedback') +
  theme_minimal(16) +
  theme(legend.position='none',
        axis.text.x=element_blank(),
        panel.grid=element_blank())
g4

# plot bottom-right subpanel (number of biomarkers)
biomarknum_tib <- 
  read_excel(XLSX_FILENAME, sheet=3, range='A45:C49',
             col_names=c('Number of biofeedback markers', 'Yes', 'No')) |>
  pivot_longer(cols=c(Yes, No), names_to='Effective?', values_to='n')

g5 <- ggplot(data=biomarknum_tib, aes(x=n, y=fct_inorder(`Number of biofeedback markers`), fill=`Effective?`)) +
  geom_bar(position='stack', stat='identity') +
  geom_label(data=biomarknum_tib |> filter(n > 0), aes(label=n), size=4, hjust=0,
             position=position_stack(vjust=0.05), fontface='bold',
             fill='white', label.size=0) +
  scale_fill_manual(values=c('Yes'=COLOR_YES, 'No'=COLOR_NO)) +
  scale_x_reverse() +
  scale_y_discrete(position='right') +
  labs(x='Number of studies', y='Number of biofeedback markers') +
  theme_minimal(16) +
  theme(legend.position='none',
        axis.text.x=element_blank(),
        panel.grid=element_blank())
g5

# finally plot everything together
# NOTE: this is not going to look good, see the actual pdf output & this
# requires post-processing to fix the layout
plot_grid(g2, NULL, g3, NULL, g1, NULL, g4, NULL, g5,
          labels=c('B', '', 'C', '', 'A', '', 'D', '', 'E'), ncol=3)
ggsave2('raw_fig3.pdf', width=18, height=18)

# for replicability purposes
sessionInfo()
