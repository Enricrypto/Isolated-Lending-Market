import { create } from "zustand";
import { persist } from "zustand/middleware";

interface SimulationStore {
  // Mode toggle
  isSimulation: boolean;
  toggleMode: () => void;
  setMode: (isSimulation: boolean) => void;
}

export const useSimulationStore = create<SimulationStore>()(
  persist(
    (set) => ({
      isSimulation: true, // Default to simulation mode

      toggleMode: () =>
        set((state) => ({
          isSimulation: !state.isSimulation,
        })),

      setMode: (isSimulation: boolean) =>
        set({
          isSimulation,
        }),
    }),
    {
      name: "lendcore-simulation-mode",
    }
  )
);
