"use client";

import { useMemo } from "react";
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  ReferenceLine,
} from "recharts";
import type { HistoryDataPoint, TimeRange } from "@/types/metrics";

interface TimeSeriesChartProps {
  data: HistoryDataPoint[];
  title: string;
  unit?: string;
  thresholds?: { value: number; label: string; color: string }[];
  height?: number;
  timeRange?: TimeRange;
  color?: string;
}

export function TimeSeriesChart({
  data,
  title,
  unit = "",
  thresholds = [],
  height = 300,
  color = "#818cf8",
}: TimeSeriesChartProps) {
  const chartData = useMemo(() => {
    return data.map((point) => ({
      ...point,
      time: new Date(point.timestamp).getTime(),
      formattedTime: formatTime(new Date(point.timestamp)),
    }));
  }, [data]);

  const yDomain = useMemo(() => {
    if (data.length === 0) return [0, 100];
    const values = data.map((d) => d.value);
    const min = Math.min(...values);
    const max = Math.max(...values);
    const padding = (max - min) * 0.1 || 10;
    return [Math.max(0, min - padding), max + padding];
  }, [data]);

  if (data.length === 0) {
    return (
      <div
        className="flex items-center justify-center rounded-xl bg-midnight-800/30 border border-midnight-700/30"
        style={{ height }}
      >
        <p className="text-slate-500 text-sm">No data available</p>
      </div>
    );
  }

  const gradientId = `gradient-${color.replace("#", "")}`;

  return (
    <div className="w-full">
      {title && (
        <h3 className="text-lg font-semibold mb-4 text-white tracking-wide">
          {title}
        </h3>
      )}
      <ResponsiveContainer width="100%" height={height}>
        <AreaChart
          data={chartData}
          margin={{ top: 5, right: 10, left: 0, bottom: 5 }}
        >
          <defs>
            <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={color} stopOpacity={0.3} />
              <stop offset="95%" stopColor={color} stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid
            strokeDasharray="3 3"
            stroke="rgba(148,163,184,0.08)"
            vertical={false}
          />
          <XAxis
            dataKey="formattedTime"
            stroke="transparent"
            fontSize={11}
            tickLine={false}
            axisLine={false}
            tick={{ fill: "#64748b", fontFamily: "monospace" }}
            dy={8}
          />
          <YAxis
            stroke="transparent"
            fontSize={11}
            tickLine={false}
            axisLine={false}
            domain={yDomain}
            tickFormatter={(value) => `${value}${unit}`}
            tick={{ fill: "#64748b", fontFamily: "monospace" }}
            width={60}
          />
          <Tooltip
            content={({ active, payload, label }) => {
              if (!active || !payload?.length) return null;
              const point = payload[0].payload;
              return (
                <div className="rounded-lg border border-midnight-700/50 bg-midnight-900/95 backdrop-blur-md px-4 py-3 shadow-xl">
                  <p className="text-[10px] font-bold text-slate-500 uppercase tracking-wider mb-1">
                    {point.timestamp
                      ? new Date(point.timestamp).toLocaleString()
                      : label}
                  </p>
                  <p className="text-lg font-semibold text-white font-mono">
                    {Number(payload[0].value).toFixed(2)}
                    <span className="text-slate-400 text-sm ml-0.5">
                      {unit}
                    </span>
                  </p>
                </div>
              );
            }}
          />

          {thresholds.map((threshold, index) => (
            <ReferenceLine
              key={index}
              y={threshold.value}
              stroke={threshold.color}
              strokeDasharray="6 4"
              strokeOpacity={0.5}
              label={{
                value: threshold.label,
                fill: threshold.color,
                fontSize: 10,
                position: "right",
                opacity: 0.7,
              }}
            />
          ))}

          <Area
            type="monotone"
            dataKey="value"
            stroke={color}
            strokeWidth={2}
            fill={`url(#${gradientId})`}
            dot={false}
            activeDot={{
              r: 5,
              fill: color,
              stroke: "rgba(255,255,255,0.2)",
              strokeWidth: 2,
            }}
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}

function formatTime(date: Date): string {
  const hours = date.getHours().toString().padStart(2, "0");
  const minutes = date.getMinutes().toString().padStart(2, "0");
  return `${hours}:${minutes}`;
}

interface TimeRangeSelectorProps {
  selected: TimeRange;
  onChange: (range: TimeRange) => void;
}

export function TimeRangeSelector({
  selected,
  onChange,
}: TimeRangeSelectorProps) {
  const ranges: TimeRange[] = ["24h", "7d", "30d"];

  return (
    <div className="flex gap-1 p-0.5 rounded-lg bg-midnight-800/50 border border-midnight-700/50">
      {ranges.map((range) => (
        <button
          key={range}
          onClick={() => onChange(range)}
          className={`px-3 py-1 rounded-md text-xs font-semibold uppercase tracking-wider transition-all ${
            selected === range
              ? "bg-indigo-500/20 text-indigo-300 border border-indigo-500/30 shadow-sm"
              : "text-slate-500 hover:text-slate-300 border border-transparent"
          }`}
        >
          {range}
        </button>
      ))}
    </div>
  );
}
