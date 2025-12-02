#!/usr/bin/env Rscript

"> 01_plot_fig2.R <

Plot a snakey Sankey diagram to illustrate the relative proportions of studies
that share similar traits across different categories.
" -> doc

setwd('~/csiro/beck/biofeedback_ir/')

suppressPackageStartupMessages({
  library(dplyr)
  library(plotly)
  library(processx)
  library(RColorBrewer)
  library(reticulate)
  library(readxl)
  library(stringr)
  library(tidyr)
})


# constants
XLSX_FILENAME <- './Supplementary Tables (S1-4).xlsx'

# read supplementary xlsx file, and select first sheet. naming of "compact"
# will be apparent later
compact_tib <- read_excel(XLSX_FILENAME, sheet=1, skip=8)

# focus on the 47 `Effective?` Yes/No studies, which also conveniently
# filters out blank rows
compact_tib <- compact_tib |> filter(`Effective?` %in% c('Effective', 'Not effective'))
table(compact_tib$`Effective?`)  # sanity check

# sankey libs all suck at mapping many-to-many relationships (e.g., many
# behaviours vs. many `Grouped biofeedback markers`). they all assume one-to-one stuff, i.e., 
# all cells can only contain a single value, NOT e.g., "Alcohol, Diet, PA".
# all three values must be on separate rows! but thankfully dplyr has a method
# to expand these rows out, phew
#
# as "Health promotion" will anchor the sankey plot, add that as a column first
compact_tib$Domain <- 'Health promotion'

# then first pick out columns that will get plotted out
compact_tib <- compact_tib |> select(
  Domain, Behaviour, `Grouped biofeedback markers`, `Communication mode`,
  `Frequency of feedback`, `BC primary outcome?`)

# visual check that things look alright first
compact_tib

# start to tidy up the df a bit, before expanding
compact_tib <- compact_tib |>
  # remove text in between parentheses
  mutate(`Grouped biofeedback markers`=str_replace(`Grouped biofeedback markers`, '\\([^()]*\\)', '')) |>
  # remove text in between parentheses again, as there's one cell with nested
  # parentheses '(())'
  mutate(`Grouped biofeedback markers`=str_replace(`Grouped biofeedback markers`, '\\([^()]*\\)', '')) |>
  # replace specific text
  mutate(`Grouped biofeedback markers`=str_replace(`Grouped biofeedback markers`, 'Heart rate / Anthro', 'Heart rate, Anthro')) |>
  mutate(`Grouped biofeedback markers`=str_replace(`Grouped biofeedback markers`, 'photographs and photoaging information', 'Photography')) |>
  mutate(`Grouped biofeedback markers`=str_replace(`Grouped biofeedback markers`, 'rate / variability', 'rate'))

# okay, expand tibble to one-value-per-row
expanded_tib <- compact_tib |>
  separate_longer_delim(Behaviour, ',') |>
  mutate(Behaviour=str_to_sentence(str_trim(Behaviour))) |>
  separate_longer_delim(`Grouped biofeedback markers`, ',') |>
  mutate(`Grouped biofeedback markers`=str_to_sentence(str_trim(`Grouped biofeedback markers`))) |>
  separate_longer_delim(`Communication mode`, ',') |>
  mutate(`Communication mode`=str_to_sentence(str_trim(`Communication mode`))) |>
  mutate(`Frequency of feedback`=str_to_sentence(str_trim(`Frequency of feedback`))) |>
  # fix a couple of things that shouldn't've been sentence-cased
  mutate(`Grouped biofeedback markers`=str_replace(`Grouped biofeedback markers`, 'Dhct scan', 'DHCT scan')) |>
  mutate(`Grouped biofeedback markers`=str_replace(`Grouped biofeedback markers`, 'Ct scan', 'CT scan')) |>
  mutate(`Grouped biofeedback markers`=str_replace(`Grouped biofeedback markers`, 'Ecg', 'ECG')) |>
  mutate(`Grouped biofeedback markers`=str_replace(`Grouped biofeedback markers`, 'Hba1c', 'HbA1c')) |>
  mutate(`Grouped biofeedback markers`=str_replace(`Grouped biofeedback markers`, 'Uv ', 'UV ')) |>
  mutate(`Grouped biofeedback markers`=str_replace(`Grouped biofeedback markers`, 'Vo2max', 'VO2max')) |>
  # fix improper plurals
  mutate(`Grouped biofeedback markers`=str_replace(`Grouped biofeedback markers`, 'Genetics', 'Genetic')) |>
  # expand certain phrases
  mutate(`Grouped biofeedback markers`=str_replace(`Grouped biofeedback markers`, 'Glucose', 'Blood glucose')) |>
  mutate(`Grouped biofeedback markers`=str_replace(`Grouped biofeedback markers`, 'Lipids', 'Blood lipids'))

# sort everything in an order that makes sense
expanded_tib <- expanded_tib |>
  arrange(desc(`BC primary outcome?`), desc(`Frequency of feedback`),
          `Communication mode`, `Grouped biofeedback markers`, Behaviour)

# check whether behaviour/grouped biofeedback markers/comms mode got prettified properly
expanded_tib |> count(Behaviour, `Grouped biofeedback markers`, `Communication mode`) |> as.data.frame()
# yup things look fine

# visual check of the tibble
expanded_tib

# plotly's way of importing data is atrocious though, need to write custom code
# to conform to their node/link ideas. see the baseline suggested code at
#   https://plotly.com/r/sankey-diagram/
#
# the first node has to be manually defined, everything else would be auto
node_tib <- tibble(node_id=0, label='Health promotion', group='Domain', color='#fdae6b')
link_tib <- tibble(source=numeric(), target=numeric(), n=numeric(), color=character())

# functions are placed here rather than the start of script so that "node_tib"
# and "link_tib" can be used in the functions
process_one_to_one <- function(lhs_group, rhs_group,
                               color='#333333', palette_interpolate=FALSE) {
  # for columns containing multiple values, assume they are comma-separated;
  # use `dplyr`'s "separate_longer_delim" on compact_tib to expand rows out
  # for downstream tallying
  count_tib <- expanded_tib |>
    count({{lhs_group}}, {{rhs_group}}, sort=FALSE)
  
  # create temp versions of node_tib and link_tib, which can then be rbinded
  # into the main tibbles
  #
  # numbering of nodes start from the largest value of node_tib + 1
  new_nodes <- unique(pull(count_tib, {{rhs_group}}))
  node_values <- (max(node_tib$node_id)+1):(max(node_tib$node_id)+length(new_nodes))
  group_name <- deparse(substitute(rhs_group))
  temp_node_tib <- tibble(
    node_id=node_values,
    label=new_nodes,
    group=group_name)
  if (all(startsWith(color, '#'))) {
    temp_node_tib$color <- color
  } else {
    # assume name of a colorbrewer has been provided
    if (palette_interpolate) {
      # the lighter end of the palette tends to be too light
      # hack is, expand the palette to 1.30x what's needed, then discard the
      # lighter-coloured 30%
      temp_col_palette <- colorRampPalette(brewer.pal(9, color))(as.integer(nrow(temp_node_tib) * 1.3))
      temp_node_tib$color <- temp_col_palette[(length(temp_col_palette)-nrow(temp_node_tib)+1):(length(temp_col_palette))]
    } else {
      temp_node_tib$color <- brewer.pal(n=nrow(temp_node_tib), name=color)
    }
  }
  
  # merge node_tib and temp_node_tib so that left joins can generate temp_link_tib
  node_tib <- bind_rows(node_tib, temp_node_tib)
  
  temp_link_tib <- count_tib |>
    left_join(select(node_tib, node_id, label), by=join_by({{lhs_group}}==label)) |>
    rename(source=node_id) |>
    left_join(select(node_tib, node_id, label), by=join_by({{rhs_group}}==label)) |>
    rename(target=node_id) |>
    # strip connecting source to target inherit source's colour
    left_join(select(node_tib, node_id, color), by=join_by(source==node_id)) |>
    select(-{{lhs_group}}, -{{rhs_group}})
  
  link_tib <- bind_rows(link_tib, temp_link_tib)
  
  # return both tibbles in a list, so they can be merged with the master tibbles
  return(list(
    count_tib=count_tib, # debug
    node_tib=node_tib,
    link_tib=link_tib))
}


# link up columns going from LHS to RHS
temp <- process_one_to_one(Domain, Behaviour,
                           color='BuGn', palette_interpolate=TRUE)
node_tib <- temp$node_tib
link_tib <- temp$link_tib

temp <- process_one_to_one(Behaviour, `Grouped biofeedback markers`,
                           color='RdPu', palette_interpolate=TRUE)
node_tib <- temp$node_tib
link_tib <- temp$link_tib

temp <- process_one_to_one(`Grouped biofeedback markers`, `Communication mode`, color='Set1')
node_tib <- temp$node_tib
link_tib <- temp$link_tib

temp <- process_one_to_one(`Communication mode`, `Frequency of feedback`,
                           color=c('#f1a340', '#998ec3'))
node_tib <- temp$node_tib
link_tib <- temp$link_tib

temp <- process_one_to_one(`Frequency of feedback`, `BC primary outcome?`,
                           color=c('#e9a3c9', '#a1d76a'))
node_tib <- temp$node_tib
link_tib <- temp$link_tib


# finally! plot the sankey plot
fig <- plot_ly(
  type='sankey',
  orientation='h',
  valueformat='d',
  valuesuffix=' studies',
  
  node = list(
    label=node_tib$label,
    color=node_tib$color,
    pad=15,
    thickness=20,
    line = list(
      color=node_tib$color,
      width = 0.5
    )
  ),
  
  link = list(
    source=link_tib$source,
    target=link_tib$target,
    value=link_tib$n,
    # alpha is defined by appending two chars at the end of the hex code
    color=paste0(link_tib$color, '80')
  )
)

# increase font size, add extra annotations
fig <- fig |>
  layout(font=list(size=20)) |>
  add_annotations('<b>Domain</b>', x=0, y=1, yshift=20, xanchor='center', showarrow=FALSE) |>
  add_annotations('<b>Behaviour</b>', x=0.2, y=1, yshift=20, xanchor='center', showarrow=FALSE) |>
  add_annotations('<b>Grouped biofeedback<br />markers</b>', x=0.4, y=1, yshift=20, xanchor='center', showarrow=FALSE) |>
  add_annotations('<b>Communication<br />mode</b>', x=0.6, y=1, yshift=20, xanchor='center', showarrow=FALSE) |>
  add_annotations('<b>Frequency of<br />feedback</b>', x=0.8, y=1, yshift=20, xanchor='center', showarrow=FALSE) |>
  add_annotations('<b>BC primary<br />outcome?</b>', x=1, y=1, yshift=20, xanchor='center', showarrow=FALSE)

# save the fig
# orca() is deprecated--use kaleido [as of Dec 2025]
# NOTE: the `save_image` command will ONLY work with kaleido 0.2.1. other
# version (0.1.0, 1.x) are folly
# package installation using reticulate is all kinds of broken; run these two
# commands on the command line
# $ conda create -n kaleido python=3.9
# $ conda install python-kaleido==0.2.* plotly==4.*

# run this code once the 'kaleido' conda env has been created + 2 packages
condaenv_exists('kaleido')  # should be TRUE
use_condaenv(condaenv='kaleido')
py_run_string('import sys')  # <-- this hack is needed to make code run
# trust me. errors weren't informative. original error was '`{reticulate}` wasn't able to find a Python environment.'
# hack from https://stackoverflow.com/questions/73604954/error-when-using-python-kaleido-from-r-to-convert-plotly-graph-to-static-image

# when scale=1, width/height values are in pixels
save_image(fig, file='raw_fig2.pdf', width=1400, height=700, scale=1)

# use a smaller font size for HTML output
#+ fig.width=9, fig.height=6
fig |> layout(font=list(size=14))

# for replicability purposes
sessionInfo()
