# Tutorials

## Modeling, Partitioning, and Solving a Natural Gas Network Optimal Control Problem with PIPS-NLP

```math
\begin{aligned}
    \min_{ \substack{ \{ \eta_{\ell,t},f_{j,d,t} \} \\ \ell \in \mathcal{L}_c, d \in \mathcal{D}_j, j \in \mathcal{J}, t \in \mathcal{T}}} \quad &
    \sum_{\substack{\ell \in \mathcal{L}_c \\ t \in \mathcal{T}}} \alpha_{\ell} P_{\ell,t} -
    \sum_{\substack{d \in \mathcal{D}_j, j \in \mathcal{J}, \\  t \in \mathcal{T}}} \alpha_{j,d} f_{j,d,t} &\\
     s.t. \quad & \text{Junction Limits} &  \\
     & \text{Pipeline Dynamics}  &  \\
     & \text{Compressor Equations} &  \\
     & \text{Network Link Equations} & 
\end{aligned}
```
