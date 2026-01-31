"use client";

import { Check, Loader2, Circle, ArrowRight } from "lucide-react";

export type StepStatus = "pending" | "active" | "completed" | "error";

export interface TransactionStep {
  label: string;
  description: string;
  status: StepStatus;
  txHash?: string;
}

interface TransactionStepperProps {
  steps: TransactionStep[];
}

export function TransactionStepper({ steps }: TransactionStepperProps) {
  return (
    <div className="space-y-0">
      {steps.map((step, index) => {
        const isLast = index === steps.length - 1;

        return (
          <div key={index} className="flex gap-3">
            {/* Step indicator + line */}
            <div className="flex flex-col items-center">
              <StepIcon status={step.status} />
              {!isLast && (
                <div
                  className={`w-px flex-1 min-h-[24px] ${
                    step.status === "completed"
                      ? "bg-emerald-500/50"
                      : "bg-midnight-700/50"
                  }`}
                />
              )}
            </div>

            {/* Step content */}
            <div className={`pb-4 ${isLast ? "pb-0" : ""}`}>
              <div className="flex items-center gap-2">
                <span
                  className={`text-sm font-medium ${
                    step.status === "completed"
                      ? "text-emerald-400"
                      : step.status === "active"
                      ? "text-white"
                      : step.status === "error"
                      ? "text-red-400"
                      : "text-slate-500"
                  }`}
                >
                  {step.label}
                </span>
                {step.status === "active" && (
                  <ArrowRight className="w-3 h-3 text-indigo-400" />
                )}
              </div>
              <p
                className={`text-xs mt-0.5 ${
                  step.status === "completed"
                    ? "text-emerald-500/70"
                    : step.status === "active"
                    ? "text-slate-400"
                    : "text-slate-600"
                }`}
              >
                {step.description}
              </p>
              {step.txHash && (
                <a
                  href={`https://sepolia.etherscan.io/tx/${step.txHash}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[10px] text-indigo-400 hover:text-indigo-300 mt-1 inline-block font-mono"
                >
                  {step.txHash.slice(0, 10)}...{step.txHash.slice(-8)}
                </a>
              )}
            </div>
          </div>
        );
      })}
    </div>
  );
}

function StepIcon({ status }: { status: StepStatus }) {
  switch (status) {
    case "completed":
      return (
        <div className="w-6 h-6 rounded-full bg-emerald-500/20 border border-emerald-500/40 flex items-center justify-center flex-shrink-0">
          <Check className="w-3.5 h-3.5 text-emerald-400" />
        </div>
      );
    case "active":
      return (
        <div className="w-6 h-6 rounded-full bg-indigo-500/20 border border-indigo-500/40 flex items-center justify-center flex-shrink-0">
          <Loader2 className="w-3.5 h-3.5 text-indigo-400 animate-spin" />
        </div>
      );
    case "error":
      return (
        <div className="w-6 h-6 rounded-full bg-red-500/20 border border-red-500/40 flex items-center justify-center flex-shrink-0">
          <span className="text-red-400 text-xs font-bold">!</span>
        </div>
      );
    default:
      return (
        <div className="w-6 h-6 rounded-full bg-midnight-800 border border-midnight-700/50 flex items-center justify-center flex-shrink-0">
          <Circle className="w-2.5 h-2.5 text-slate-600" />
        </div>
      );
  }
}
