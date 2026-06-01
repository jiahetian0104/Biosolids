# 计算 soil concentration（ng/g）
library(tidyr)
library(ggplot2)
library(dplyr)
library(plotly)

# 设置PFAS的回归斜率
pfas_data <- data.frame(
  PFAS = c("PFHxA", "PFHpA", "PFOA", "PFNA", "PFDA", "PFHxS", "PFOS"),
  Slope = c(0.003, 0.003, 0.015, 0.003, 0.009, 0.004, 0.198)
)

# 创建 biosolids loading rate 序列
loading_rate <- seq(0, 100, by = 1)

# 展开数据框
plot_data <- expand.grid(LoadingRate = loading_rate, PFAS = pfas_data$PFAS) %>%
  left_join(pfas_data, by = "PFAS") %>%
  mutate(SoilConcentration = Slope * LoadingRate)

# 画图
ggplot(plot_data, aes(x = LoadingRate, y = SoilConcentration, color = PFAS)) +
  geom_line(size = 1.2) +
  labs(
    title = "PFAS Soil Concentration vs. Biosolids Loading Rate",
    x = "Biosolids Loading Rate (Mg/ha)",
    y = "Soil Concentration (ng/g)",
    color = "PFAS"
  ) +
  theme_minimal(base_size = 14)

plot <- plot_ly()

for (pfas in unique(plot_data$PFAS)) {
  sub_data <- filter(plot_data, PFAS == pfas)
  plot <- plot %>%
    add_trace(
      x = sub_data$LoadingRate,
      y = sub_data$SoilConcentration,
      type = 'scatter',
      mode = 'lines',
      name = pfas
    )
}

# 添加布局
plot <- plot %>%
  layout(
    title = "PFAS Soil Concentration vs. Biosolids Loading Rate",
    xaxis = list(title = "Biosolids Loading Rate (Mg/ha)"),
    yaxis = list(title = "Soil Concentration (ng/g)"),
    legend = list(title = list(text = "PFAS"))
  )

plot
