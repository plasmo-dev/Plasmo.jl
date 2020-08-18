# Tutorials

## Modeling, Partitioning, and Solving a Natural Gas Network Optimal Control Problem with PIPS-NLP

### Junction OptiGraph
The gas junction model is described by the below equations, where ``\theta_{j,t}`` is the pressure at junction
``j`` and time interval ``t``. ``\underline{\theta}_j`` is the lower pressure bound for the
junction, ``\overline{\theta}_j`` is the upper pressure bound, ``f_{j,d,t}^{target}`` is the target demand flow for demand ``d`` on junction ``j``
and ``\overline{f}_{j,s}`` is the available gas generation from supply ``s`` on junction ``j``.

```math
\begin{aligned}
    & \underline{\theta}_n \le \theta_{j,t} \le \overline{\theta}_n , \quad j \in \mathcal{J}, \ t \in \mathcal{T}   \\
    &0 \le f_{j,d,t} \le f_{j,d,t}^{target}, \quad d \in \mathcal{D}_j, \ j \in \mathcal{J}, \ t \in \mathcal{T} \\
    &0 \le f_{j,s,t} \le \overline{f}_{j,s}, \quad s \in \mathcal{S}_j, \ j \in \mathcal{J}, \ t \in \mathcal{T}
\end{aligned}
```


### Network OptiGraph
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
