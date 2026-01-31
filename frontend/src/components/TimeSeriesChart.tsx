"use client";

import { useMemo } from "react";
import {
  LineChart,
  Line,
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
}

export function TimeSeriesChart({
  data,
  title,
  unit = "",
  thresholds = [],
  height = 300,
}: TimeSeriesChartProps) {
  // Format data for recharts
  const chartData = useMemo(() => {
    return data.map((point) => ({
      ...point,
      time: new Date(point.timestamp).getTime(),
      formattedTime: formatTime(new Date(point.timestamp)),
    }));
  }, [data]);

  // Calculate Y-axis domain
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
        className="flex items-center justify-center bg-gray-50 dark:bg-gray-800 rounded-lg"
        style={{ height }}
      >
        <p className="text-gray-500 dark:text-gray-400">No data available</p>
      </div>
    );
  }

  return (
    <div className="w-full">
      <h3 className="text-lg font-semibold mb-4 text-gray-900 dark:text-white">
        {title}
      </h3>
      <ResponsiveContainer width="100%" height={height}>
        <LineChart
          data={chartData}
          margin={{ top: 5, right: 30, left: 20, bottom: 5 }}
        >
          <CartesianGrid strokeDasharray="3 3" stroke="#374151" opacity={0.3} />
          <XAxis
            dataKey="formattedTime"
            stroke="#9CA3AF"
            fontSize={12}
            tickLine={false}
          />
          <YAxis
            stroke="#9CA3AF"
            fontSize={12}
            tickLine={false}
            domain={yDomain}
            tickFormatter={(value) => `${value}${unit}`}
          />
          <Tooltip
            contentStyle={{
              backgroundColor: "#1F2937",
              border: "none",
              borderRadius: "8px",
              color: "#F9FAFB",
            }}
            labelFormatter={(_, payload) => {
              if (payload && payload[0]) {
                return new Date(payload[0].payload.timestamp).toLocaleString();
              }
              return "";
            }}
            formatter={(value: number) => [`${value.toFixed(2)}${unit}`, "Value"]}
          />

          {/* Threshold reference lines */}
          {thresholds.map((threshold, index) => (
            <ReferenceLine
              key={index}
              y={threshold.value}
              stroke={threshold.color}
              strokeDasharray="5 5"
              label={{
                value: threshold.label,
                fill: threshold.color,
                fontSize: 12,
                position: "right",
              }}
            />
          ))}

          <Line
            type="monotone"
            dataKey="value"
            stroke="#3B82F6"
            strokeWidth={2}
            dot={false}
            activeDot={{ r: 4, fill: "#3B82F6" }}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}

// Helper to format time for X-axis
function formatTime(date: Date): string {
  const hours = date.getHours().toString().padStart(2, "0");
  const minutes = date.getMinutes().toString().padStart(2, "0");
  return `${hours}:${minutes}`;
}

// Time range selector component
interface TimeRangeSelectorProps {
  selected: TimeRange;
  onChange: (range: TimeRange) => void;
}

export function TimeRangeSelector({ selected, onChange }: TimeRangeSelectorProps) {
  const ranges: TimeRange[] = ["24h", "7d", "30d"];

  return (
    <div className="flex gap-2">
      {ranges.map((range) => (
        <button
          key={range}
          onClick={() => onChange(range)}
          className={`px-3 py-1 rounded-md text-sm font-medium transition-colors ${
            selected === range
              ? "bg-blue-500 text-white"
              : "bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-600"
          }`}
        >
          {range}
        </button>
      ))}
    </div>
  );
}
