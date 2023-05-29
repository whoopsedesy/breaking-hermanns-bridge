library("tidyverse")

WORKS <- tribble(
	~work,         ~num_lines, ~date, ~work_name,
	"Argon.",            5834,  -350, "Argonautica",
	"Callim.Hymn",        941,  -250, "Callimachus’ Hymns",
	"Dion.",            21356,   450, "Nonnus’ Dionysiaca",
	"Hom.Hymn",          2342,  -600, "Homeric Hymns",
	"Il.",              15683,  -750, "Iliad",
	"Od.",              12107,  -750, "Odyssey",
	"Phaen.",            1155,  -250, "Aratus’ Phaenomena",
	"Q.S.",              8801,   350, "Quintus of Smyrna’s Fall of Troy",
	"Sh.",                479,  -550, "Shield",
	"Theoc.",            2527,  -250, "Theocritus’ Idylls",
	"Theog.",            1042,  -750, "Theogony",
	"W.D.",               831,  -750, "Works and Days",
)

# TODO: fix off-by-one in BCE dates.
PERIODS <- tribble(
	~start, ~end, ~name,
	  -800, -500, "Archaic",     # https://en.wikipedia.org/wiki/Classical_antiquity#Archaic_period_(c._8th_to_c._6th_centuries_BC)
	  -323, -146, "Hellenistic", # https://en.wikipedia.org/wiki/Classical_antiquity#Hellenistic_period_(323%E2%80%93146_BC)
	  -100,  500, "Imperial",    # https://en.wikipedia.org/wiki/Classical_antiquity#Hellenistic_period_(323%E2%80%93146_BC)
)

# Read input and tidy.
data <- read_csv(
	"HB_Database_Predraft.csv",
	col_types = cols(
		work = col_factor(),
		book_n = col_character(),
		line_n = col_character()
	)
) %>%
	mutate(
		across(c(breaks_hb_schein, is_speech), ~ recode(.x, "Yes" = TRUE, "No" = FALSE)),
		enclitic = recode(enclitic, "Enclitic" = TRUE, `Non-enclitic` = FALSE),
		book_n = as_factor(sprintf("%s%s", work, book_n))
	)

# Sanity check that some columns that are supposed to be constant within a line
# are actually constant.
inconsistent <- data %>%
	group_by(work, book_n, line_n) %>%
	summarize(across(c(caesura_word_n, breaks_hb_schein, speaker, is_speech), ~ length(unique(.x))), .groups = "drop") %>%
	filter(caesura_word_n != 1 | breaks_hb_schein != 1 | speaker != 1 | is_speech != 1)
if (nrow(inconsistent) != 0) {
	print(inconsistent)
	stop()
}

break_rates <- data %>%
	# Keep one representative row per line of verse.
	filter(word_n == caesura_word_n) %>%

	# Count up breaks per work.
	group_by(work) %>%
	summarize(
		num_breaks = sum(breaks_hb_schein),
		num_caesurae = n(),
		.groups = "drop"
	) %>%

	# Join with table of per-work metadata.
	left_join(WORKS, by = c("work")) %>%

	# Sort in decreasing order by break rate, then by ascending by date,
	# then ascending by work name.
	arrange(desc(num_breaks / num_lines), date, work_name)

# Output development table of break rates and caesura rates.
break_rates %>%
	bind_rows(break_rates %>%
		summarize(
			across(c(num_breaks, num_caesurae, num_lines), sum),
			work = "total"
		)
	) %>%
	transmute(
		`work` = work,
		`L` = num_lines,
		`C` = num_caesurae,
		`B` = num_breaks,
		`C/L%` = sprintf("%.3f%%", 100 * num_caesurae / num_lines),
		`B/C%` = sprintf("%.3f%%", 100 * num_breaks / num_caesurae),
		`B/L%` = sprintf("%.3f%%", 100 * num_breaks / num_lines),
	)

cat("lines without and with enclitic:")
table((data %>%
	filter(breaks_hb_schein) %>%
	group_by(work, book_n, line_n) %>%
	summarize(enclitic = any(enclitic), .groups = "drop")
)$enclitic)
cat("breaks/quasi-breaks in speech/not-speech:\n")
table(data %>%
	filter(word_n == caesura_word_n) %>%
	select(breaks_hb_schein, is_speech))

# Scatterplot of breaks per caesura and caesurae per line.
p <- ggplot(break_rates,
	aes(
		x = num_breaks / num_caesurae,
		y = num_caesurae / num_lines,
		label = work
	)
) +

	geom_point(alpha = 0.8) +
	geom_text(hjust = 0, nudge_x = 0.001) +

	scale_x_continuous(
		labels = scales::label_percent(accuracy = 1.0),
		breaks = seq(0, max(with(break_rates, num_breaks / num_caesurae)), 0.02)
	) +
	scale_y_continuous(
		labels = scales::label_percent(accuracy = 1.0),
		breaks = seq(0, max(with(break_rates, num_caesurae / num_lines)), 0.02)
	) +
	coord_fixed(
		# Make room for labels at the top and right.
		xlim = c(0, max(with(break_rates, num_breaks / num_caesurae)) + 0.015),
		ylim = c(0, max(with(break_rates, num_caesurae / num_lines)) + 0.002),
		expand = FALSE,
		clip = "off"
	) +
	labs(
		x = "rate of breaks per caesura",
		y = "rate of caesurae per line"
	) +
	theme_minimal()
ggsave("breaks_vs_caesurae_rates.png", p, width = 7, height = 4)

# Plot of breaks per line over time.
p <- ggplot(break_rates,
	aes(
		x = date,
		y = num_breaks / num_lines,
		label = work
	)
) +

	geom_rect(
		data = PERIODS,
		inherit.aes = FALSE,
		aes(
			xmin = start,
			xmax = end,
			ymin = 0.0045,
			ymax = 0.0050
		),
		alpha = 0.2
	) +
	geom_text(
		data = PERIODS,
		inherit.aes = FALSE,
		aes(
			x = (start + end) / 2,
			y = (0.0045 + 0.0050) / 2,
			label = name
		),
		size = 3
	) +

	geom_point(alpha = 0.8) +
	geom_text(hjust = 0, nudge_x = 10) +

	scale_x_continuous(labels = scales::label_number(accuracy = 1)) +
	scale_y_continuous(labels = scales::label_percent(accuracy = 0.1)) +
	coord_cartesian(
		xlim = with(break_rates, c(min(date) - 50, max(date) + 75)),
		# ylim = c(0, max(with(break_rates, num_breaks / num_lines))),
		expand = FALSE,
		clip = "off"
	)+
	labs(
		x = "year",
		y = "rate of breaks per line"
	) +
	theme_minimal()
ggsave("break_rates_over_time.png", p, width = 7, height = 3)

# Output publication table of breaks per work.
break_rates %>%
	transmute(
		`Work` = work_name,
		`Lines` = scales::comma(num_lines, accuracy = 1),
		`Caesurae` = scales::comma(num_caesurae, accuracy = 1),
		`Breaks` = scales::comma(num_breaks, accuracy = 1),
		`Breaks/Line` = ifelse(num_breaks == 0,
			sprintf("\u00a0%.g%%", 100 * num_breaks / num_lines),
			sprintf("\u00a0%.2f%%", 100 * num_breaks / num_lines)
		),
		`_` = ifelse(num_breaks == 0,
			"",
			sprintf("(1\u00a0per\u00a0%s)", scales::comma(num_lines / num_breaks, accuracy = 1))
		),
	) %>%

	write_csv("break_rates.csv") %>% print()
