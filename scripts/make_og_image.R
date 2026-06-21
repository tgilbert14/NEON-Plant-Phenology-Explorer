#----------------------------------------------------------------------
# make_og_image.R — draws docs/og-image.png (1200x630), the social card for
# the landing page. Self-contained base-R graphics in the Desert Data Labs
# "Field Notebook" palette (forest green + senescence amber on a deep canopy
# ground), with a faint phenology-clock arc of phenophase colours for texture.
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" scripts/make_og_image.R
#----------------------------------------------------------------------
ROOT <- getwd()
out  <- file.path(ROOT, "docs", "og-image.png")
dir.create(dirname(out), showWarnings = FALSE, recursive = TRUE)

forest <- "#1f6f3e"; forest2 <- "#14532a"; deep <- "#0e2c1a"
amber <- "#d98014"; parch <- "#f6f3ea"
# phenophase ramp (mirror of pheno_palette): green-up -> leaf -> bloom -> fruit -> senesce
ramp <- c("#9ccf6a", "#1f7a3f", "#c8417a", "#6a3fa0", "#d98014")

png(out, width = 1200, height = 630, res = 144)
op <- par(mar = c(0, 0, 0, 0), bg = forest); on.exit({ par(op); dev.off() })
plot.new(); plot.window(xlim = c(0, 1200), ylim = c(0, 630), xaxs = "i", yaxs = "i")

# background: deep canopy with a soft top-left glow
rect(0, 0, 1200, 630, col = forest, border = NA)
for (i in seq(0, 1, length.out = 60))
  symbols(150, 560, circles = 30 + i * 820, inches = FALSE, add = TRUE,
          bg = grDevices::adjustcolor(forest2, alpha.f = 0.013), fg = NA)
rect(0, 0, 1200, 90, col = grDevices::adjustcolor(deep, .5), border = NA)

# a faint "phenology clock" of overlapping phenophase petals, bottom-right
cx <- 1010; cy <- 250
draw_petal <- function(ang0, span, r, col) {
  th <- seq(ang0, ang0 + span, length.out = 40) * pi / 180
  xs <- c(cx, cx + cos(th) * r); ys <- c(cy, cy + sin(th) * r)
  polygon(xs, ys, col = grDevices::adjustcolor(col, alpha.f = 0.16), border = NA)
}
set.seed(7)
for (k in seq_along(ramp))
  draw_petal((k - 1) * 70 + 12, 64, 150 + k * 14, ramp[k])
# month tick ring
for (a in seq(0, 330, by = 30)) {
  th <- a * pi / 180
  segments(cx + cos(th) * 232, cy + sin(th) * 232, cx + cos(th) * 244, cy + sin(th) * 244,
           col = grDevices::adjustcolor("white", .18), lwd = 2)
}

# badge
text(70, 556, "NEON · PLANT PHENOLOGY OBSERVATIONS · DP1.10055.001",
     col = grDevices::adjustcolor(amber, .96), cex = .9, font = 2, adj = 0)

# title
text(68, 470, "NEON Plant Phenology", col = "white", cex = 3.4, font = 2, adj = 0)
text(68, 394, "Explorer",             col = "white", cex = 3.4, font = 2, adj = 0)
# a small leaf accent after the wordmark
points(322, 396, pch = 21, bg = grDevices::adjustcolor(ramp[1], .95), col = NA, cex = 2.4)

# subtitle
text(70, 320, "When the leaves break, the flowers open, and the canopy turns — every",
     col = grDevices::adjustcolor("white", .92), cex = 1.12, adj = 0)
text(70, 290, "tagged plant NEON watches, week by week, across the country.",
     col = grDevices::adjustcolor("white", .92), cex = 1.12, adj = 0)

# stat chips
chips <- list(c("46", "field sites"), c("9,515", "tagged plants"),
              c("499", "species"), c("10+", "years of records"))
x0 <- 70; gap <- 14; w <- 250; h <- 96; y1 <- 64
for (i in seq_along(chips)) {
  xl <- x0 + (i - 1) * (w + gap)
  rect(xl, y1, xl + w, y1 + h, col = grDevices::adjustcolor("white", .10), border = NA)
  rect(xl, y1, xl + 6, y1 + h, col = amber, border = NA)                 # amber spine
  text(xl + 22, y1 + 62, chips[[i]][1], col = "white", cex = 1.9, font = 2, adj = 0)
  text(xl + 22, y1 + 28, chips[[i]][2], col = grDevices::adjustcolor("white", .85), cex = .94, adj = 0)
}
cat("wrote", out, "\n")
