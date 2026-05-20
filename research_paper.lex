\documentclass[11pt, a4paper]{article}

\usepackage[utf8]{inputenc}
\usepackage{geometry}
\geometry{margin=1in}
\usepackage{amsmath}
\usepackage{apacite}
\usepackage{titlesec}
\usepackage{setspace}
\usepackage{amsfonts}
\usepackage{natbib}
\usepackage{hyperref}
\usepackage{algorithm}
\usepackage{algpseudocode}
\usepackage{graphicx}
\usepackage{booktabs}
\usepackage{threeparttable} 
\usepackage{comment}
\usepackage{float}

\usepackage{subcaption}

\title{\textbf{Biased Targeting for Global Quotas (BTGQ): Fair Treatment Allocation under Capacity Constraints}} 
\author{Marc Bilanin 601448 \\ Aaron Wong Zi Shian 658399 \\ Marwa EL Maaroufi 639759\\ Richárd Peőcz 598495 \\\\ Erasmus University Rotterdam \\ BSc Econometrics and Operations Research}
\date{\today}

\begin{document}
\begin{spacing}{1.15}
\maketitle


\section{Introduction}

The Maritime Inventory Routing Problem (MIRP) is an integrated planning problem in which shipping companies must jointly decide vessel routes, port visit sequences, service times, and cargo movements while respecting inventory constraints at ports and on vessels over a finite planning horizon. In contrast to standard vehicle routing settings, routing choices in MIRP immediately affect future inventory feasibility, berth availability, and the timing of subsequent operations. This strong interdependence makes MIRP both practically relevant and computationally difficult, especially in maritime settings such as liquefied natural gas, bulk commodity transport, and other energy-related supply chains where shortages, overflows, and delayed deliveries are costly.

The topic is relevant from both a scientific and a practical perspective. Scientifically, MIRP sits at the intersection of routing, scheduling, and inventory control, making it a useful test bed for studying how heuristics can handle tightly coupled operational decisions. Practically, maritime operators need methods that produce high-quality solutions within limited planning time, often without the computational burden or licensing requirements associated with large commercial optimization solvers. Recent review articles, such as Fagerholt et al. (2023), emphasize that this need is becoming more urgent as maritime logistics expands into new applications related to energy transport and decarbonization.

This thesis focuses on replicating the recent open-source heuristic proposed by Sanghikian et al. (2026), which combines Beam Search (BS) and Iterated Local Search (ILS) for the deterministic, finite-horizon, single-product MIRP. Their contribution is important because most successful MIRP heuristics are matheuristics that rely on mathematical programming components and commercial solvers, whereas their BS-ILS framework is designed as a self-contained heuristic method. In particular, the original paper introduces a greedy randomized procedure for evaluating partial solutions during the beam search phase, a tailored solution representation, and problem-specific neighborhoods for local improvement.

The main research question of this replication study is whether the performance of the BS-ILS framework can be reproduced in an independent Julia implementation on the public MIRPLib benchmark instances considered in the original article. More specifically, the thesis investigates whether the reported solution quality, feasibility, and computational behavior can be matched on MIRPLib Group 2 instances, and which components of the heuristic appear to matter most for its overall effectiveness. This framing follows the logic of a thesis proposal: it identifies a concrete research problem, explains why the question is relevant, and links the methodological choice directly to an observable benchmark setting.

The empirical setting is well suited for replication. MIRPLib, introduced by Papageorgiou et al. (2014), provides standardized benchmark instances for single-product maritime inventory routing problems and has become the main reference point for method comparison in this literature. The original BS-ILS paper evaluates all 72 Group 2 instances, which are deterministic long-horizon problems with one loading port, multiple discharge ports, heterogeneous vessels, and no split pickups or deliveries. Because the dataset and benchmark structure are public, the study offers a transparent basis for checking reproducibility and for assessing whether a solver-free heuristic can remain competitive on difficult large-scale instances.

The contribution of this thesis is therefore twofold. First, it provides a structured replication of a recent MIRP heuristic that has direct methodological relevance for open-source operations research. Second, it evaluates the robustness of the proposed algorithmic design in a setting where practical usability matters as much as raw solution quality. By doing so, the thesis contributes to the broader discussion on reproducibility in heuristic optimization and on the role of lightweight, accessible methods for complex maritime planning problems.

\section{Literature Review}

\subsection{The Maritime Inventory Routing Problem}

The MIRP concerns the joint planning of maritime transportation and inventory management. Rather than deciding routes independently from stock evolution, the decision maker must coordinate vessel movements with the changing inventory levels at loading and unloading ports. Christiansen and Fagerholt (2009) describe this interaction as a defining feature of maritime logistics planning, since vessel schedules determine when cargo can be loaded or delivered, while inventory limits determine whether those schedules are feasible in the first place. As a result, MIRP formulations usually include routing, timing, loading and unloading quantities, and inventory balance constraints within a single integrated model.

Over time, the MIRP literature has expanded into a broad family of variants that reflect different industrial settings. Papageorgiou et al. (2014) note that instances may differ in the number of products, the structure of the supply network, the use of spot charters, whether split pickups or deliveries are allowed, and whether the setting is deterministic or stochastic. To make methods more comparable, they introduced MIRPLib, a public benchmark library that standardizes a range of single-product MIRP instances. This benchmark has become especially important because it provides a common basis for evaluating algorithms under clearly defined operational assumptions.

For this thesis, the most relevant benchmark class is MIRPLib Group 2. These instances model deterministic, long-horizon, single-product problems with one loading port and multiple unloading ports. They are operationally challenging because the long planning horizon and tight inventory interactions create many opportunities for downstream infeasibility, even when a local routing decision initially appears attractive. That difficulty helps explain why MIRP research has often prioritized sophisticated exact methods, decomposition approaches, and hybrid heuristics.

\subsection{Heuristic and Matheuristic Approaches}

The MIRP literature includes exact methods, heuristics, metaheuristics, and matheuristics, but heuristic performance has historically depended heavily on mathematical programming support. Early work by Ronen (2002) introduced a cost-based heuristic for maritime planning, while later studies developed more specialized search procedures for inventory-routing settings. Examples include the multi-start local search of Stalhane et al. (2012), the fix-and-relax heuristic of Uggen et al. (2013), and iterative heuristic approaches for LNG shipping and inventory management such as Goel et al. (2015). These studies show that problem-specific construction and improvement logic can generate strong solutions, but they also highlight how difficult it is to maintain feasibility in tightly constrained maritime systems.

As the field developed, metaheuristics and matheuristics became more prominent. Christiansen et al. (2011) combined a construction heuristic with a genetic algorithm for a multi-product MIRP, while later studies introduced rolling-horizon heuristics, large neighborhood search, variable neighborhood search, and local branching mechanisms. Agra et al. (2016, 2017, 2018) proposed several MIP-based heuristic and matheuristic frameworks, and Sanghikian et al. (2021) developed a variable neighborhood search that still relied on linear programming to optimize continuous decisions for fixed routing structures. These approaches often achieve strong results, but they typically depend on mathematical programming components, which can increase implementation complexity and reduce transparency for replication.

The benchmark-oriented MIRPLib literature reinforces this pattern. Papageorgiou et al. (2018) proposed several hybrid approaches for MIRPLib Group 2, including rolling-horizon heuristics, local branching, and solution-polishing procedures, and reported new best-known solutions for a substantial share of open instances. Munguia et al. (2019) later introduced the Parallel Alternating Criteria Search, a large-neighborhood-search-based approach that produced strong benchmark performance. Additional MIRPLib-focused contributions, such as Friske and Buriol (2020) and Friske et al. (2022), also relied on decomposition and mathematical-programming-guided improvement procedures. Taken together, this literature suggests that MIRP benchmark success has been driven mainly by hybrid methods rather than by stand-alone heuristics.

Recent review papers by Shaabani et al. (2023) and Fagerholt et al. (2023) confirm that solver-supported heuristics remain dominant, especially for large and operationally realistic instances. They also emphasize that future MIRP research should balance model richness with computational tractability and practical usability. This observation creates a clear motivation for studying methods that are both competitive and easy to reproduce. If a self-contained heuristic can deliver strong results on standard benchmarks, it becomes attractive not only for academic comparison but also for practice-oriented settings in which solver access is limited.

Within this context, the contribution of Sanghikian et al. (2026) is particularly relevant. Their paper proposes a BS-ILS heuristic specifically tailored to MIRPLib Group 2 and reports that the method can solve all 72 benchmark instances without relying on mathematical programming. The paper further reports improvements over the previous best-known solutions for 18 instances, with competitive average gaps on the remaining cases. From a literature perspective, the method therefore occupies an important position: it does not replace the broader matheuristic tradition, but it shows that a carefully designed open-source heuristic may achieve comparable performance on a difficult MIRP benchmark. This makes the paper a strong candidate for replication, because validating such a claim is valuable for both methodological credibility and future heuristic development.



\end{document}
