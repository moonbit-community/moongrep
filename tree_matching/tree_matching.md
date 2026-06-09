# Pattern Matching in Trees
树模式匹配

Christoph M. Hoffmann and Michael J. O'Donnell
Christoph M. Hoffmann 和 Michael J. O'Donnell
Purdue University, West Lafayette, Indiana
普渡大学，印第安纳州西拉法叶

**Abstract.** Tree pattern matching is an interesting special problem which occurs as a crucial step in a number of programming tasks, for instance, design of interpreters for nonprocedural programming languages, automatic implementations of abstract data types, code optimization in compilers, symbolic computation, context searching in structure editors, and automatic theorem proving. As with the sorting problem, the variations in requirements and resources for each application seem to preclude a uniform, universal solution to the tree-pattern-matching problem. Instead, a collection of well-analyzed techniques, from which specific applications may be selected and adapted, should be sought. Five new techniques for tree pattern matching are presented, analyzed for time and space complexity, and compared with previously known methods. Particularly important are applications where the same patterns are matched against many subjects and where a subject may be modified incrementally. Therefore, methods which spend some time preprocessing patterns in order to improve the actual matching time are included.
摘要。树模式匹配是一个有趣的特殊问题，它是许多编程任务中的关键步骤，例如：非过程化编程语言的解释器设计、抽象数据类型的自动实现、编译器中的代码优化、符号计算、结构编辑器中的上下文搜索以及自动定理证明。与排序问题一样，各应用场景在需求和资源上的差异似乎排除了树模式匹配问题的统一通用解决方案。相反，应该寻求一套经过充分分析的技术，以便针对特定应用进行选择和调整。本文提出了五种新的树模式匹配技术，分析了它们的时间和空间复杂度，并与已知方法进行了比较。特别重要的应用场景包括：同一组模式与多个主体进行匹配，以及主体可能被增量修改的情况。因此，本文也包含了通过预处理模式来缩短实际匹配时间的方法。

**Categories and Subject Descriptors:** F.2.2 \[Analysis of Algorithms and Problem Complexity\]: Nonnumerical Algorithms and Problems--pattern matching; G.2.2 \[Discrete Mathematics\]: Graph Theory--trees
类别和主题描述：F.2.2 \[算法分析和问题复杂度\]：非数值算法和问题——模式匹配；G.2.2 \[离散数学\]：图论——树

**General Terms:** Algorithms, Theory
通用术语：算法，理论

**Additional Key Words and Phrases:** incremental pattern matching, bottom-up matching, top-down matching, subtree replacement systems, interpreter generation, theorem proving
关键词和短语：增量模式匹配，自底向上匹配，自顶向下匹配，子树替换系统，解释器生成，定理证明

This work was supported in part by the National Science Foundation under Grant MCS 78-01812.
本研究工作得到国家科学基金会（National Science Foundation）MCS 78-01812 号资助项目的支持。

## 1\. Introduction
1\. 引言

Many computing techniques involve simplifying expressions (trees) by repeatedly replacing special types of subexpressions (subtrees) according to a set of replacement rules. For example,
许多计算技术涉及通过根据一组替换规则反复替换特殊类型的子表达式（子树）来简化表达式（树）。例如：

1.  Hoffmann and O'Donnell [^14] show how tree replacements may be used in automatically generated interpreters for nonprocedural programming languages. The defining equations for the programming language are taken as the replacement rules. An interpreter may then process an input expression by replacing subexpressions according to the given rules until no more replacements are possible. Interpreters may be generated which are absolutely faithful to the semantics of the language as given by the defining equations. The tree-replacement approach is very convenient for producing interpreters for existing languages such as LISP and LUCID or for implementing experimental languages. Elsewhere, the merits of the language of equations as a programming language in its own right are examined [^15].
    Hoffmann 和 O'Donnell [^14] 展示了如何将树替换用于非过程化编程语言的自动生成解释器。编程语言的定义方程被用作替换规则。解释器随后可以通过根据给定规则替换子表达式来处理输入表达式，直到无法再进行替换为止。可以生成完全忠实于定义方程所给出的语言语义的解释器。树替换方法对于为 LISP 和 LUCID 等现有语言生成解释器或实现实验性语言非常方便。在其他地方，方程语言作为一种独立编程语言的优点也得到了探讨 [^15]。
    
2.  Guttag et al. [^12] and Wand [^34] suggest that defining equations may be treated as tree replacement rules to yield direct implementations of abstract data types. Guttag et al. [^13] describe a working system based on this idea, as does Goguen [^11]. Such a system does not differ in essence from the interpreters or equational programs in (1) but in this case would be embedded into a procedural language as subroutine.
    Guttag 等人 [^12] 和 Wand [^34] 建议将定义方程视为树替换规则，以实现抽象数据类型的直接实现。Guttag 等人 [^13] 描述了一个基于此想法的运行系统，Goguen [^11] 也是如此。这样的系统在本质上与 (1) 中的解释器或等式程序没有区别，但在这种情况下，它将作为子程序嵌入到过程化语言中。
    
3.  Intermediate code produced by a compiler may be represented by trees. Certain types of code optimizations, for example, the elimination of redundant operations and constant propagation, may be viewed as replacement rules [^10][^16][^33].
    编译器生成的中间代码可以用树来表示。某些类型的代码优化，例如消除冗余操作和常量传播，可以被视为替换规则 [^10][^16][^33]。
    
4.  In [^7] Collins represents algebraic terms as trees and formulates symbolic computation as tree replacements. The replacement rules formalize operations such as differentiation and certain algebraic simplifications.
    在 [^7] 中，Collins 将代数项表示为树，并将符号计算公式化为树替换。这些替换规则使微分和某些代数简化等操作正式化。
    
5.  One approach to the automatic proving of equational theorems is to treat a set of equational axioms as replacement rules and transform one side of the equation to be proved into the other by a sequence of tree replacements. Knuth and Bendix [^20] discuss some of the cases in which tree replacements yield efficient theorem provers. Most studies of equational theorem proving, such as [^9][^22][^25][^31], have not used the replacement system approach. Chew [^6] has recently developed an algorithm combining replacement systems with the methods of Nelson and Oppen [^25].
    自动证明等式定理的一种方法是将一组等式公理视为替换规则，并通过一系列树替换将待证明等式的一侧转换为另一侧。Knuth 和 Bendix [^20] 讨论了树替换产生高效定理证明器的一些案例。大多数关于等式定理证明的研究，如 [^9][^22][^25][^31]，都没有使用替换系统方法。Chew [^6] 最近开发了一种将替换系统与 Nelson 和 Oppen [^25] 的方法相结合的算法。
    

Many of the theoretical properties of tree replacement systems have been studied in [^3a][^11][^23][^26][^30]. In this paper we develop theoretically and practically efficient algorithms for one of the key technical issues in implementing replacement systems.
树替换系统的许多理论特性已在 [^3a][^11][^23][^26][^30] 中进行了研究。在本文中，我们为实现替换系统的关键技术问题之一，开发了理论和实践上都高效的算法。

An implementation of a tree replacement system requires practical solutions for the following:
树替换系统的实现需要针对以下问题提供实际的解决方案：

*   (a) a method for finding subtrees which may be replaced;
    (a) 一种寻找可被替换子树的方法；
*   (b) a way of choosing the next replacement to be performed;
    (b) 一种选择下一次执行替换操作的方式；
*   (c) a way of actually replacing the subtree.
    (c) 一种实际替换子树的方式。

Part (c) is an easy programming problem; (b) is a question which is quite complicated in its theoretical effects. It has been treated abstractly in [^26] and algorithmically in [^14]. Part (a) is the subject of this paper.
部分 (c) 是一个简单的编程问题；(b) 是一个理论影响相当复杂的问题，在 [^26] 中进行了抽象讨论，在 [^14] 中进行了算法化讨论。部分 (a) 则是本文的主题。

A large part of the overhead in implementing tree replacements comes from the repeated searching for the next subtree to be replaced. This is essentially a tree-pattern-matching problem. We believe that good solutions to the problem of tree pattern matching are a prerequisite for making implementations based on tree replacements competitive in efficiency with ad hoc methods, especially in the realm of interpreters for nonprocedural languages.
实现树替换的大部分开销源于重复搜索下一个待替换的子树。这本质上是一个树模式匹配问题。我们认为，树模式匹配问题的良好解决方案是使基于树替换的实现在效率上能与权宜方法（ad hoc methods）竞争的前提，特别是在非过程化语言的解释器领域。

Tree pattern matching is analogous to the problem of pattern matching in strings studied in [^1][^4][^21]. We consider two essentially different ways of extending the Knuth-Morris-Pratt string-matching algorithm to tree patterns, each with several variations.
树模式匹配类似于 [^1][^4][^21] 中研究的字符串模式匹配问题。我们考虑了将 Knuth-Morris-Pratt 字符串匹配算法扩展到树模式的两种本质不同的方法，每种方法都有若干变体。

One may view first-order unification as a tree-pattern-matching problem [^3][^28][^29]. However, first-order unification differs from the tree pattern matching considered here in that a pattern is matched against the entire subject tree and not against proper subtrees as well. Pattern matching in our sense has been studied in [^18][^23][^24][^27]. With the exception of [^23], these papers examine the problem without considering the specific requirements of subtree replacement systems. Karp et al. [^18] give an algorithm which finds all matches of a pattern tree to subtrees of a subject. By preprocessing the pattern(s) involved we get more efficient methods. Recently, Overmars and van Leeuwen [^27] have studied tree pattern matching, but with a different class of trees. They discovered independently many of the techniques we develop in Section 8, and their fastest algorithm has a performance equal to our Algorithm D. We discuss their results and the relationship to our work in Section 9. Kron's work [^23] is related to the bottom-up techniques of Sections 3 and 4. We discuss the details at the end of Section 4.
人们可以将一阶合一（first-order unification）视为一个树模式匹配问题 [^3][^28][^29]。然而，一阶合一与此处考虑的树模式匹配不同，因为它的模式是与整个主体树进行匹配，而不是同时也与真子树进行匹配。我们所定义的模式匹配已在 [^18][^23][^24][^27] 中得到研究。除 [^23] 外，这些论文在研究该问题时均未考虑子树替换系统的特定需求。Karp 等人 [^18] 提供了一种算法，可以找到模式树与主体子树的所有匹配项。通过对涉及的模式进行预处理，我们可以获得更高效的方法。最近，Overmars 和 van Leeuwen [^27] 研究了树模式匹配，但针对的是不同类别的树。他们独立发现了我们在第 8 节中开发的许多技术，且其最快算法的性能与我们的算法 D 相当。我们将在第 9 节讨论他们的研究结果及其与我们工作的关系。Kron 的工作 [^23] 与第 3 节和第 4 节的自底向上技术相关。我们将在第 4 节末尾讨论其细节。

In applications of tree replacements the same set of rules is typically used many times. Preprocessing of the rules is advantageous if it speeds up their application. Each replacement causes a local change in the subject tree. So our pattern-matching techniques should be able to respond incrementally to local changes in the subject to avoid repeated rescanning of the entire tree. For the sake of a simple presentation we discuss each algorithm in terms of a static subject first and then introduce adaptations to handle changing subjects.
在树替换的应用中，同一组规则通常会被多次使用。如果对规则进行预处理能加快其应用速度，那么预处理就是有益的。每次替换都会导致目标树（subject tree）发生局部变化。因此，我们的模式匹配技术应该能够对目标的局部变化做出增量响应，以避免对整棵树进行重复扫描。为了便于演示，我们先讨论针对静态目标的每种算法，然后再介绍处理动态目标的改进方案。

In Section 2 we precisely define the matching problem and our criteria for a good solution. The remainder of the paper divides into two parts, corresponding to the two basic approaches we give. Sections 3-7 develop the bottom-up approach to pattern matching. Here we match in a subject tree by traversing it from the leaves to the root. This method is a significant generalization of the Knuth-Morris-Pratt string-matching algorithm. In Sections 8 and 9 we give our second approach, matching top down by traversing the subject root to leaves. While the bottom-up method generalizes string matching, the top-down method reduces tree matching to a string-matching problem.
在第 2 节中，我们精确定义了匹配问题以及衡量优秀解决方案的标准。本文的其余部分分为两个部分，分别对应我们给出的两种基本方法。第 3-7 节开发了模式匹配的自底向上（bottom-up）方法。在这种方法中，我们通过从叶节点到根节点的遍历在目标树中进行匹配。该方法是 Knuth-Morris-Pratt 字符串匹配算法的重要推广。在第 8 节和第 9 节中，我们给出了第二种方法，即通过从根节点到叶节点的遍历进行自顶向下（top-down）匹配。自底向上方法推广了字符串匹配，而自顶向下方法则将树匹配简化为字符串匹配问题。

The bottom-up method is characterized by more expensive preprocessing but faster matching and a better response to local changes. It is developed from the notion of match sets--sets of subpatterns which match at a particular tree node. The basic matching algorithm is introduced in Section 3. Properties of match sets are studied in Section 4. Since it turns out that certain tree patterns have exponentially many different match sets, which would lead to an exponential preprocessing algorithm, we introduce in Section 5 a restriction on tree patterns which allows efficient preprocessing algorithms. Section 6 gives the preprocessing algorithm and discusses its relationship with the preprocessing algorithms in [^1][^21]. In Section 7 we sketch a better preprocessing algorithm for binary tree patterns.
自底向上方法的特点是预处理成本较高，但匹配速度更快，且对局部变化的响应更好。它是基于“匹配集”（match sets）的概念开发的——即在特定树节点处匹配的子模式集合。第 3 节介绍了基本的匹配算法。第 4 节研究了匹配集的性质。由于某些树模式具有指数级数量的不同匹配集，这会导致指数级的预处理算法，因此我们在第 5 节中对树模式引入了一种限制，从而允许高效的预处理算法。第 6 节给出了预处理算法，并讨论了其与 [^1][^21] 中预处理算法的关系。在第 7 节中，我们简述了一种针对二叉树模式的更好的预处理算法。

Sections 8 and 9 give our top-down algorithm and discuss possible improvements. These algorithms have better preprocessing times than the bottom-up method, but the matching times and update behavior are inferior to the bottom-up method. Tree patterns are reduced to strings which are matched along paths in the subject, as in [^18]. The preprocessing for this technique is little more than the preprocessing algorithm for string matching [^1]. The basic idea of the top-down method lies in the use of counters for coordinating the matches of different path strings. This counting also turns out to be the limiting factor of the algorithm and is responsible for the worst-case bound. We can improve this bound on machines with bit-string operations, as indicated in Section 9.
第 8 节和第 9 节给出了我们的自顶向下算法并讨论了可能的改进。这些算法的预处理时间优于自底向上方法，但匹配时间和更新性能不如自底向上方法。如 [^18] 中所述，树模式被简化为字符串，并沿目标树中的路径进行匹配。该技术的预处理工作仅比字符串匹配的预处理算法 [^1] 略多。自顶向下方法的基本思想在于使用计数器来协调不同路径字符串的匹配。这种计数也成为了该算法的限制因素，并导致了最坏情况下的界限。如第 9 节所示，在具有位串（bit-string）操作的机器上，我们可以改善这一界限。

For the restricted class of tree patterns introduced in Section 5 we have preprocessing algorithms which require
对于第 5 节中引入的受限类树模式，我们的预处理算法需要

$$
O(\mathit{patsize}^2 + \mathit{patsize}^{\mathit{rank}} \cdot \mathit{ht})
$$

steps. Here $patsize$ is the sum of the pattern sizes, $ht$ the height of a specific tree which has to be constructed as part of preprocessing, and $rank$ the highest rank in the alphabet. In the worst case $ht$ may be as big as $patsize$. The actual match, bottom up, requires $O(subsize + match)$ time, where $subsize$ is the size of the subject tree and $match$ is the number of matches found. For binary alphabets we have a preprocessing algorithm which requires only $O(patsize * ht^2)$ steps when coupled with a modified bottom-up matching algorithm requiring
步。这里 $patsize$ 是模式大小的总和， $ht$ 是作为预处理的一部分必须构建的特定树的高度，而 $rank$ 是字母表中的最高秩。在最坏情况下， $ht$ 可能高达 $patsize$ 。实际的自底向上匹配需要 $O(subsize + match)$ 时间，其中 $subsize$ 是主体树的大小， $match$ 是找到的匹配数量。对于二元字母表，我们有一种预处理算法，当结合改进的自底向上匹配算法时，仅需 $O(patsize * ht^2)$ 步。

$$
O(\mathit{subsize} \cdot \mathit{ht} + \mathit{match})
$$

For top-down matching we have an $O(patsize)$ preprocessing algorithm. Here we need no restrictions on the tree patterns. The matching requires
对于自顶向下匹配，我们有一种 $O(patsize)$ 预处理算法。这里我们不需要对树模式进行任何限制。匹配过程需要

$$
O(\mathit{subsize} \cdot \mathit{suf} \cdot \mathit{patno})
$$

steps, where $suf$ is a quantity depending on the structure of the pattern suffixes (at most equal to the maximum height of a pattern) and $patno$ is the number of tree patterns to be matched. For machines with bit-string operations we can, within the same time bound for preprocessing, match using a different technique in only $O(subsize * patno)$ steps. If each pattern has a height not exceeding the number of bits in a machine word, then this algorithm is of practical importance.
步，其中 $suf$ 是取决于模式后缀结构的量（最多等于模式的最大高度），而 $patno$ 是待匹配的树模式数量。对于具有位串操作的机器，在相同的预处理时间限制内，我们可以使用不同的技术在仅 $O(subsize * patno)$ 步内完成匹配。如果每个模式的高度不超过机器字中的位数，那么该算法具有实际意义。

In Section 10 we discuss other possibilities of bottom-up tree pattern matching on machines with bit-string operations, and a trade-off principle for matching time versus preprocessing time and space.
在第 10 节中，我们将讨论在具有位串操作的机器上进行自底向上树模式匹配的其他可能性，以及匹配时间与预处理时间和空间之间的权衡原则。

## 2\. The Tree-Matching Problem
2\. 树匹配问题

We are given a finite ranked alphabet $\Sigma$ of function symbols, including constants as nullary functions. $S$ denotes the set of $\Sigma$\-terms, formally defined as follows.
给定一个由函数符号组成的有限有秩字母表 $\Sigma$ ，其中包括作为零元函数的常量。 $S$ 表示 $\Sigma$ -项的集合，其形式定义如下。

**Definition 2.1
定义 2.1**

1.  For all $b$ in $\Sigma$ of rank 0, $b$ is a $\Sigma$\-term.
    对于 $\Sigma$ 中所有秩为 0 的 $b$ ， $b$ 是一个 $\Sigma$ -项。
2.  If $a$ is a symbol of rank $q$ in $\Sigma$, then $a(t_1, \ldots, t_q)$ is a $\Sigma$\-term provided each of the $t_i$ is.
    如果 $a$ 是 $\Sigma$ 中一个秩为 $q$ 的符号，且每个 $t_i$ 都是 $\Sigma$ -项，那么 $a(t_1, \ldots, t_q)$ 也是一个 $\Sigma$ -项。
3.  Nothing else is a $\Sigma$\-term.
    除此之外，没有其他内容是 $\Sigma$ -项。

We view $\Sigma$\-terms as labeled ordered trees. Thus the term $a(a(b, b), b)$ is the tree of Figure 1. Note that the trees $a(a(b, b), b)$ and $a(b, a(b, b))$ are considered to be different. In the following we use "$\Sigma$\-tree" and "$\Sigma$\-term" interchangeably.
我们将 $\Sigma$ -项视为带标签的有向树。因此，项 $a(a(b, b), b)$ 即为图 1 所示的树。注意，树 $a(a(b, b), b)$ 和 $a(b, a(b, b))$ 被视为是不同的。在下文中，我们交替使用“ $\Sigma$ -树”和“ $\Sigma$ -项”。

**Figure 1.** Tree for $a(a(b, b), b)$.
图 1. $a(a(b, b), b)$ 的树结构。

We are also given a special nullary symbol $v$, not in $\Sigma$, to serve as placeholder for any $\Sigma$\-tree. We define the set of $\Sigma \cup \{v\}$\-terms just as $\Sigma$\-terms but add to (i) that $v$ is a $\Sigma \cup \{v\}$\-term. $S_v$ denotes the set of $\Sigma \cup \{v\}$\-terms.
我们还给定了一个特殊的零元符号 $v$ （不在 $\Sigma$ 中），用作任何 $\Sigma$ -树的占位符。我们定义 $\Sigma \cup \{v\}$ -项集的方式与 $\Sigma$ -项完全相同，但在 (i) 中补充规定 $v$ 也是一个 $\Sigma \cup \{v\}$ -项。 $S_v$ 表示 $\Sigma \cup \{v\}$ -项的集合。

**Definition 2.2.** A tree pattern is any term in $S_v$. If $b(t_1, \ldots, t_q)$ is a term, then define $\operatorname{son}_i(b(t_1, \ldots, t_q))$ to be $t_i$ for $1 \le i \le q$.
定义 2.2。树模式是指 $S_v$ 中的任何项。如果 $b(t_1, \ldots, t_q)$ 是一个项，则定义 $\operatorname{son}_i(b(t_1, \ldots, t_q))$ 为 $t_i$ ，其中 $1 \le i \le q$ 。

We now explain how tree patterns are to be matched in $\Sigma$\-trees.
我们现在解释树模式如何与 $\Sigma$ -树进行匹配。

**Definition 2.3.** A pattern $p$ in $S_v$ with $k$ occurrences of the symbol $v$ matches a subject tree $t$ in $S$ at node $n$ if there exist $\Sigma$\-trees $t_1, \ldots, t_k$ in $S$ (not necessarily the same) such that the $\Sigma$\-tree $p'$, obtained from $p$ by substituting $t_i$ for the $i$th occurrence of $v$ in $p$, is equal to the subtree of $t$ rooted at $n$.
定义 2.3。如果存在 $S$ 中的 $\Sigma$ 树 $t_1, \ldots, t_k$ （不一定相同），使得通过将 $p$ 中第 $i$ 次出现的 $v$ 替换为 $t_i$ 而得到的 $\Sigma$ 树 $p'$ 等于 $t$ 中以 $n$ 为根的子树，则称 $S_v$ 中包含 $k$ 个符号 $v$ 的模式 $p$ 匹配 $S$ 中位于节点 $n$ 处的受体树 $t$ 。

**Example 2.1.** Consider the pattern $p = a(a(b, v), v)$, with two occurrences of the symbol $v$, and the $\Sigma$\-tree $t = a(a(b, c), a(a(b, b), b))$. Then $p$ matches $t$ at the two nodes marked in Figure 2. For the match at the root, the trees $t_1$ and $t_2$ to be substituted in $p$ are $t_1 = c$ and $t_2 = a(a(b, b), b)$. For the match at the marked interior node we have $t_1 = b$ and $t_2 = b$.
示例 2.1。考虑包含两个符号 $v$ 的模式 $p = a(a(b, v), v)$ ，以及 $\Sigma$ 树 $t = a(a(b, c), a(a(b, b), b))$ 。那么 $p$ 在图 2 中标记的两个节点处匹配 $t$ 。对于根节点处的匹配，要在 $p$ 中替换的树 $t_1$ 和 $t_2$ 分别是 $t_1 = c$ 和 $t_2 = a(a(b, b), b)$ 。对于标记的内部节点处的匹配，我们有 $t_1 = b$ 和 $t_2 = b$ 。

**Figure 2.** (a) Subject tree. (b) Pattern.
图 2。(a) 受体树。(b) 模式。

We wish to solve a matching problem in which we are given a finite set of patterns $p_1, \ldots, p_k$ from $S_v$ and a subject tree $t$ from $S$ and are asked to identify in $t$ every node at which any of the $p_i$ match.
我们希望解决一个匹配问题，即给定一组来自 $S_v$ 的有限模式集 $p_1, \ldots, p_k$ 和一个来自 $S$ 的受体树 $t$ ，并要求在 $t$ 中识别出任何 $p_i$ 匹配的所有节点。

**Definition 2.4 (The Matching Problem).** A matching problem consists of a finite set of patterns $p_1, \ldots, p_k$ in $S_v$ and a subject tree $t$ in $S$. A solution to a matching problem is a list of all the pairs $(n, i)$, where $n$ is a node in $t$ and $p_i$ matches at $n$.
定义 2.4（匹配问题）。匹配问题由 $S_v$ 中的有限模式集 $p_1, \ldots, p_k$ 和 $S$ 中的主体树 $t$ 组成。匹配问题的解是所有对 $(n, i)$ 的列表，其中 $n$ 是 $t$ 中的一个节点，且 $p_i$ 在 $n$ 处匹配。

Our definition is motivated principally by algorithmic problems arising in the implementation of subtree replacement systems. Allowing different substitutions for different occurrences of $v$ is equivalent to using a different variable symbol at each occurrence. This restriction is motivated by theoretical problems which arise when repeated variables are permitted in the specification of the replacement axioms [^26], Sec. VII.
我们的定义主要源于子树替换系统实现中出现的算法问题。允许对 $v$ 的不同出现进行不同的替换，等同于在每次出现时使用不同的变量符号。这一限制源于在替换公理的规范中允许重复变量时所产生的理论问题 [^26], Sec. VII。

Note that $S_v$ contains $S$ as subset. Thus every $\Sigma$\-tree is also a pattern. We develop our results assuming patterns contain at least one occurrence of $v$, since patterns without variable occurrences are uninteresting from a practical viewpoint. This assumption does not limit our results.
注意 $S_v$ 包含 $S$ 作为子集。因此，每棵 $\Sigma$ 树也是一个模式。我们在开发研究结果时假设模式至少包含一次 $v$ 的出现，因为从实际角度来看，不含变量出现的模式是乏味的。这一假设并不会限制我们的结果。

Our matching problem is in some ways more specific, and in some ways more general, than first-order unification. Our use of $v$ corresponds to allowing terms with nonrepeated variables as patterns, while in first-order unification repeated variables are allowed and variables may also appear in the subject. On the other hand, in unification only two trees are matched against each other, and only at the root, whereas we match any number of patterns anywhere in the subject tree.
在某些方面，我们的匹配问题比一阶合一（first-order unification）更具体，而在另一些方面则更通用。我们对 $v$ 的使用对应于允许将具有非重复变量的项作为模式，而在一阶合一中，允许重复变量，且变量也可能出现在主体中。另一方面，在合一中，只有两棵树相互匹配，且仅在根节点处匹配，而我们是在主体树的任何位置匹配任意数量的模式。

**Definition 2.5.** The size of a tree is the total number of subtrees (equivalently, nodes) in it. The size of a forest is the sum of the sizes of all trees in it. The height of a tree is the number of edges in a longest path from the root to a leaf of the tree.
定义 2.5。树的大小是其中子树（等价地，节点）的总数。森林的大小是其中所有树的大小之和。树的高度是从根节点到该树叶节点的最长路径上的边数。

We are especially interested in applications in which the set of patterns remains fixed and is to be matched against a sequence of subject trees. We therefore consider preprocessing the tree patterns and distinguish preprocessing time, involving operations on the patterns independent of any subject tree, and matching time, involving all subject dependent operations. Minimizing matching time is the first priority. Preprocessing time is then minimized with respect to a fixed process for matching. Trade-offs between preprocessing time and matching time are considered if the improvement in preprocessing is dramatic and the degradation in matching is small. We also consider the space requirements in preprocessing and matching.
我们特别感兴趣的是模式集保持不变，并需要与一系列目标树进行匹配的应用场景。因此，我们考虑对树模式进行预处理，并区分预处理时间（涉及独立于任何目标树的模式操作）和匹配时间（涉及所有与目标树相关的操作）。最小化匹配时间是首要任务。随后，在固定匹配过程的前提下最小化预处理时间。如果预处理效率有显著提升且匹配性能下降微小，我们也会考虑预处理时间与匹配时间之间的权衡。此外，我们还考虑了预处理和匹配过程中的空间需求。

We are especially interested in algorithms which may clearly be adapted to assimilate local changes to the subject without rescanning the entire tree. For bottom-up matching we achieve linear matching times, but preprocessing time may be exponential. To keep bottom-up preprocessing time polynomial, we need some additional constraints on patterns. For top-down matching we lower the preprocessing time to linear, with no restrictions on patterns, at the cost of a slight increase in matching time. The bottom-up method adapts more easily to changes in the subject.
我们特别感兴趣的是那些能够清晰地适应目标树局部变化，而无需重新扫描整棵树的算法。对于自底向上匹配，我们实现了线性匹配时间，但预处理时间可能是指数级的。为了使自底向上的预处理时间保持在多项式级别，我们需要对模式添加一些额外的约束。对于自顶向下匹配，我们在不对模式做任何限制的情况下，将预处理时间降低到了线性级别，代价是匹配时间略有增加。自底向上的方法更容易适应目标树的变化。

For the remainder of this paper, complexities will be expressed in terms of:
在本文的其余部分，复杂度将根据以下各项来表示：

| Term术语 | Meaning含义 |
| --- | --- |
| patnopatnopatno | the number of different patterns involved涉及的不同模式数量 |
| patsizepatsizepatsize | the size of the pattern forest模式森林的大小 |
| subsizesubsizesubsize | the size of the subject tree主题树的大小 |
| symsymsym | the number of symbols in the alphabet Σ\\SigmaΣ字母表 Σ\\SigmaΣ 中的符号数量 |
| rankrankrank | the highest rank (arity) of any symbol in Σ\\SigmaΣ Σ\\SigmaΣ 中任意符号的最大秩（元数） |
| matchmatchmatch | the number of matches which are found找到的匹配数量 |

All suggested methods for tree matching should be compared to the naive algorithm (based on a simple form of unification), which merely tries every pattern at every position in the subject tree. The naive algorithm does no preprocessing but takes $O(patsize * subsize)$ matching time.
所有建议的树匹配方法都应与朴素算法（基于简单形式的合一）进行比较，该算法仅尝试在主体树的每个位置匹配每个模式。朴素算法不进行预处理，但需要 $O(patsize * subsize)$ 的匹配时间。

## 3\. The Bottom-Up Matching Algorithm
3\. 自底向上匹配算法

The key idea of the bottom-up matching algorithm is to find, at each point in the subject tree, all patterns and all parts of patterns which match at this point. Let $n$ be a node in the subject labeled with the $q$\-ary symbol $b$, and suppose we wish to compute the set $M$ of all those pattern subtrees other than $v$ which match at $n$ in the sense of Definition 2.3. (Since $v$ matches anywhere, we always have a match of $v$.) Suppose we have already computed such sets for each of the sons of $n$, and call these sets, from left to right, $M_1, \ldots, M_q$. Then $M$ contains $v$ plus exactly those pattern subtrees $b(t_1, \ldots, t_q)$ such that $t_i$ is in $M_i$ for $1 \le i \le q$. Therefore we could compute $M$ by forming trees $b(t_1, \ldots, t_q)$ for all combinations $(t_1, \ldots, t_q)$, where the $t_i$ are chosen from $M_i$, and then asking whether each candidate for membership in $M$ is a subpattern. Once we have assigned these sets to each node in the subject tree, we have essentially solved the matching problem, since each match is signaled by the presence of a complete pattern in some set.
自底向上匹配算法的核心思想是在主体树的每个点上，找出在该点匹配的所有模式及模式的所有部分。设 $n$ 是主体树中标记为 $q$ 元符号 $b$ 的一个节点，假设我们希望计算所有在 $n$ 处匹配（符合定义 2.3）的模式子树（除 $v$ 之外）的集合 $M$ 。（由于 $v$ 可以匹配任何地方，我们总能得到 $v$ 的匹配。）假设我们已经为 $n$ 的每个子节点计算了此类集合，并将这些集合从左到右依次称为 $M_1, \ldots, M_q$ 。那么 $M$ 包含 $v$ 以及恰好满足以下条件的模式子树 $b(t_1, \ldots, t_q)$ ：对于 $1 \le i \le q$ ， $t_i$ 位于 $M_i$ 中。因此，我们可以通过为所有组合 $(t_1, \ldots, t_q)$ （其中 $t_i$ 选自 $M_i$ ）构建树 $b(t_1, \ldots, t_q)$ ，然后询问 $M$ 的每个候选成员是否为子模式，从而计算出 $M$ 。一旦我们为主体树中的每个节点分配了这些集合，我们就基本上解决了匹配问题，因为每个匹配都由某个集合中完整模式的出现来标记。

Note that there can be only finitely many such sets $M$, because both $\Sigma$ and the set of subpatterns are finite. Thus we could precompute these sets, code them by some enumeration, and then construct tables. Given a node symbol $b$ and the codes of the $M_i$, these tables give the code for $M$. In the case of a $q$\-ary symbol $b$, we would have a $q$\-dimensional matrix for that symbol.
注意，此类集合 $M$ 只能有有限个，因为 $\Sigma$ 和子模式集合都是有限的。因此，我们可以预先计算这些集合，通过某种枚举对其进行编码，然后构建表格。给定节点符号 $b$ 和 $M_i$ 的代码，这些表格将给出 $M$ 的代码。对于 $q$ 元符号 $b$ ，我们将为该符号建立一个 $q$ 维矩阵。

Given such tables, the matching algorithm becomes trivial: Traverse the subject tree in postorder and assign to each node $n$ the code $c$ representing the set of partial matches at $n$ as discussed. The tables consist of arrays, one for each alphabet symbol. If node $n$ is labeled with the $q$\-ary symbol $b$, then the $q$\-dimensional array for $b$ is used. The code $c$ at $n$ is the value indexed by the tuple $(c_1, \ldots, c_q)$ where $c_i$ is the code assigned to the $i$th son of $n$ (from the left). If the set represented by $c$ contains the pattern $p_i$, then the pair $(n, i)$ is added to the solution.
有了这些表，匹配算法就变得非常简单：以后序遍历目标树，并为每个节点 $n$ 分配代码 $c$ ，该代码代表如前所述在 $n$ 处的偏匹配集合。这些表由数组组成，每个字母表符号对应一个数组。如果节点 $n$ 被标记为 $q$ 元符号 $b$ ，则使用 $b$ 的 $q$ 维数组。 $n$ 处的代码 $c$ 是由元组 $(c_1, \ldots, c_q)$ 索引的值，其中 $c_i$ 是分配给 $n$ 的第 $i$ 个儿子（从左起）的代码。如果由 $c$ 表示的集合包含模式 $p_i$ ，则将对 $(n, i)$ 添加到解集中。

The matching time of this algorithm is clearly $O(subsize)$ for computing all codes plus $O(match)$ for listing the solution. The constant of linearity involves one array reference for computing the codes, a single test to determine whether a complete pattern match is present, plus the overhead for the postorder traversal. Note that the codes may be assigned so that all codes indicating matches are contiguous. The space requirements depend on the table size and are discussed in Section 4.
该算法的匹配时间显然是计算所有代码所需的 $O(subsize)$ 加上列出解集所需的 $O(match)$ 。线性常数涉及计算代码时的一次数组引用、确定是否存在完整模式匹配的一次测试，以及后序遍历的开销。请注意，代码的分配可以使得所有指示匹配的代码都是连续的。空间需求取决于表的大小，将在第 4 节中讨论。

**Example 3.1.** Consider a matching problem in which the patterns
示例 3.1。考虑一个匹配问题，其中需要匹配模式

$$
p_1 = a(a(v, v), b) \quad \text{and} \quad p_2 = a(b, v)
$$

are to be matched. Assume the alphabet $\Sigma$ is ${a, b, c}$, where $a$ is binary and $b$ and $c$ are nullary symbols. For reasons to be explained later, of the thirty-two possible sets of pattern subtrees only the following five can arise as result of matching:
。假设字母表 $\Sigma$ 为 ${a, b, c}$ ，其中 $a$ 是二元符号， $b$ 和 $c$ 是零元符号。由于稍后解释的原因，在三十二个可能的模式子树集合中，只有以下五个会在匹配过程中出现：

$$
\begin{aligned} \text{Set 1} &= \{v\},\\ \text{Set 2} &= \{b, v\},\\ \text{Set 3} &= \{a(v, v), v\},\\ \text{Set 4} &= \{a(b, v), a(v, v), v\},\\ \text{Set 5} &= \{a(a(v, v), b), a(v, v), v\}. \end{aligned}
$$

**Figure 3.** Tables for node labels $a$, $b$, and $c$.
图 3. 节点标签 $a$ 、 $b$ 和 $c$ 的表。

| Left son左子节点 | Right son 1右子节点 1 | Right son 2右子节点 2 | Right son 3右子节点 3 | Right son 4右子节点 4 | Right son 5右子节点 5 |
| --- | --- | --- | --- | --- | --- |
| 1 | 3 | 3 | 3 | 3 | 3 |
| 2 | 4 | 4 | 4 | 4 | 4 |
| 3 | 3 | 5 | 3 | 3 | 3 |
| 4 | 3 | 5 | 3 | 3 | 3 |
| 5 | 3 | 5 | 3 | 3 | 3 |

Table for node label $b$: $2$
节点标签 $b$ 的表： $2$
Table for node label $c$: $1$
节点标签 $c$ 的表： $1$

Thus, assigning a 4 to some node $n$ of a subject would indicate that each of the members of Set 4 matches at $n$. In particular, $p_2$ matches. Assigning 5 implies a match of $p_1$.
因此，为主题的某个节点 $n$ 分配 4 将表示集合 4 的每个成员都在 $n$ 处匹配。特别地， $p_2$ 匹配。分配 5 则意味着 $p_1$ 匹配。

Figure 3 shows the tables for $a$, $b$, and $c$. For instance, the entry at $(3, 2)$ in the table for $a$ is 5, because at the left son we have a match of both $a(v, v)$ and $v$, and at the right son we have a match of both $b$ and of $v$. For the nullary symbols $b$ and $c$ the tables are 0-dimensional, consisting of one entry each.
图 3 展示了 $a$ 、 $b$ 和 $c$ 的表。例如， $a$ 的表中 $(3, 2)$ 处的条目为 5，因为在左子节点处我们同时匹配了 $a(v, v)$ 和 $v$ ，而在右子节点处我们同时匹配了 $b$ 和 $v$ 。对于零元符号 $b$ 和 $c$ ，其表是 0 维的，各包含一个条目。

**Figure 4.** Complete assignment of codes using the bottom-up algorithm.
图 4. 使用自底向上算法完成的代码分配。

Figure 4 shows the complete assignment of codes when using the bottom-up algorithm with these tables. Note that $p_1$ matches at the node with code 5 and $p_2$ at the node with code 4.
图 4 展示了使用这些表进行自底向上算法时的完整代码分配。请注意， $p_1$ 在代码为 5 的节点处匹配，而 $p_2$ 在代码为 4 的节点处匹配。

There is some similarity between bottom-up matching and formal parsing methods such as LR(k) parsing. In both cases a finite number of possible configurations are precomputed, and tables are formed to drive the parsing/matching process. As with LR(k) parsing, our tables will sometimes be very large, but we isolate a significant class of problems in which the table size is kept small.
自底向上匹配与诸如 LR(k) 语法分析等形式化解析方法之间存在一定的相似性。在这两种情况下，都会预先计算有限数量的可能配置，并生成表来驱动解析/匹配过程。与 LR(k) 解析一样，我们的表有时会非常庞大，但我们分离出了一类重要的问题，在这些问题中，表的大小可以保持在较小范围内。

When a local change is made to a subject tree, matching codes must be recomputed for the changed portion and some ancestors of the changed portion. In Section 4 we see that the number of ancestors whose codes must be recomputed is bounded by the largest height of a pattern. Note that in these ancestors new matches could appear or old matches disappear. Thus it seems intuitively unlikely that any method could update with less recomputation.
当对主体树进行局部修改时，必须为受影响的部分及其某些祖先节点重新计算匹配代码。在第 4 节中，我们将看到需要重新计算代码的祖先节点数量受限于模式树的最大高度。请注意，在这些祖先节点中，可能会出现新的匹配或消失旧的匹配。因此，从直觉上看，似乎不太可能有任何方法能以更少的重新计算量完成更新。

## 4\. Pattern Relations and Match Sets
4\. 模式关系与匹配集

We now turn to studying the sets of partial matches used in the bottom-up matching algorithm of Section 3. We begin by precisely defining these sets and deriving properties which we will later exploit in designing good preprocessing algorithms.
我们现在转而研究第 3 节中自底向上匹配算法所使用的部分匹配集合。我们首先精确定义这些集合，并推导出一些性质，这些性质将在稍后设计优秀的预处理算法时被我们所利用。

**Definition 4.1.** Let $F = {p_1, \ldots, p_k}$ be a set of patterns in $S_v$ and $PF$ the set of all subtrees of the $p_i$. A subset $M$ of $PF$ is a match set for $F$ if there exists a tree $t$ in $S$ such that every pattern in $M$ matches $t$ at the root and every pattern in $PF - M$ does not match $t$ at the root.
定义 4.1。令 $F = {p_1, \ldots, p_k}$ 为 $S_v$ 中的模式集合， $PF$ 为 $p_i$ 的所有子树集合。如果存在 $S$ 中的树 $t$ ，使得 $M$ 中的每个模式都在根节点处与 $t$ 匹配，且 $PF - M$ 中的每个模式都不在根节点处与 $t$ 匹配，则 $PF$ 的子集 $M$ 是 $F$ 的一个匹配集。

Note that if $v$ is in $PF$, then $v$ is in every match set. Observe also that the concept of match sets depends on the pattern forest $F$.
注意，如果 $v$ 在 $PF$ 中，那么 $v$ 就在每一个匹配集中。同时请观察到，匹配集的概念取决于模式森林 $F$ 。

**Example 4.1.** Consider the pattern forest $F = {p_1, p_2}$, where $p_1$ and $p_2$ are as in Example 3.1. Then the set $M = {a(b, v), a(v, v), v}$ is a match set because of the tree $a(b, c)$. However, $M' = {a(b, v), v}$ is not a match set, because a match of $a(b, v)$ implies a match of $a(v, v)$ at the same node.
示例 4.1。考虑模式森林 $F = {p_1, p_2}$ ，其中 $p_1$ 和 $p_2$ 如示例 3.1 所示。那么集合 $M = {a(b, v), a(v, v), v}$ 是一个匹配集，因为存在树 $a(b, c)$ 。然而， $M' = {a(b, v), v}$ 不是一个匹配集，因为 $a(b, v)$ 的匹配意味着在同一个节点上必然存在 $a(v, v)$ 的匹配。

Observe that the set of all possible match sets contains all sets which the bottom-up matching algorithm could assign (in encoded form) in any subject tree, given the pattern forest $F$.
观察到，所有可能匹配集的集合包含了在给定模式森林 $F$ 的情况下，自底向上匹配算法在任何目标树中可能分配（以编码形式）的所有集合。

Given $F$, let $\operatorname{Match}(t)$ denote the match set which must be assigned at the root of the subject tree $t$. $PF$ is the set of all pattern subtrees from $F$. We can now formally state the two properties on which the bottom-up matching algorithm is based.
给定 $F$ ，令 $\operatorname{Match}(t)$ 表示必须分配给目标树 $t$ 根节点的匹配集。 $PF$ 是来自 $F$ 的所有模式子树的集合。我们现在可以正式阐述自底向上匹配算法所基于的两个属性。

**Definition 4.2
定义 4.2**

1.  If $a$ is a nullary symbol, then
    如果 $a$ 是一个零元符号，那么

$$
\operatorname{Match}(a) = \begin{cases} \{a, v\} & \text{if } a \in PF,\\ \{v\} & \text{otherwise}. \end{cases}
$$

2.  If $a$ is $q$\-ary, $q > 0$, then
    如果 $a$ 是 $q$ 元的， $q > 0$ ，那么

$$
\operatorname{Match}(a(t_1, \ldots, t_q)) = \{v\} \cup \{p' \mid p' \text{ has root } a \text{ and is in } PF,\ \text{and for } 1 \le j \le q,\ \operatorname{son}_j(p') \in \operatorname{Match}(t_j)\}.
$$

Note that because of (2), $\operatorname{Match}(t)$ does not depend on any node in $t$ whose distance from the root exceeds the maximum height of a pattern. Because of this and the manner in which codes are assigned, the bottom-up matching algorithm responds well to local changes in a subject tree. See [^15] for details.
注意，由于 (2) 的缘故， $\operatorname{Match}(t)$ 不依赖于 $t$ 中与根节点距离超过模式最大高度的任何节点。正因如此以及编码分配的方式，自底向上匹配算法对主题树的局部变化具有良好的响应性。详情请参阅 [^15]。

In principle, the required enumeration of sets and tables may be generated by a simple closure strategy which starts with $\operatorname{Match}(a)$ for all nullary symbols $a$ and repeatedly closes under the operation (2) of Definition 4.2. Such an algorithm would require
原则上，所需的集合和表格枚举可以通过一种简单的闭包策略生成，该策略从所有零元符号 $a$ 的 $\operatorname{Match}(a)$ 开始，并根据定义 4.2 的操作 (2) 反复进行闭包运算。这样的算法将需要

$$
O(\mathit{set}^{\mathit{rank}+1} \cdot \mathit{sym} \cdot \mathit{patsize})
$$

time, where $set$ is the number of distinct match sets generated. The table size would be $O(set^rank * sym)$. In order to improve this time limit and to bound the size of $set$, which could be as bad as $O(2^patsize)$, we need to understand certain relations between patterns and members of match sets. We define the following relations on tree patterns.
时间复杂度为，其中 $set$ 是生成的不同匹配集（match sets）的数量。表的大小将为 $O(set^rank * sym)$ 。为了优化这一时间限制并限制 $set$ 的大小（其最坏情况可能达到 $O(2^patsize)$ ），我们需要理解模式与匹配集成员之间的某些关系。我们在树模式上定义以下关系。

**Definition 4.3.** Let $p$ and $p'$ be patterns in $S_v$. Then $p$ is inconsistent with $p'$ (written $p \parallel p'$) if there is no subject tree $t$ in $S$ with both $p$ and $p'$ in $\operatorname{Match}(t)$. $p$ and $p'$ are independent (written $p ~ p'$) if there are trees $t_1, t_2, t_3$ in $S$ such that $p$ is in $\operatorname{Match}(t_1)$, $p'$ is not in $\operatorname{Match}(t_1)$, $p$ is not in $\operatorname{Match}(t_2)$, $p'$ is in $\operatorname{Match}(t_2)$, and $p$ and $p'$ are in $\operatorname{Match}(t_3)$. $p$ subsumes $p'$ ($p \ge p'$) if, for all $t$ in $S$, $p$ in $\operatorname{Match}(t)$ implies that $p'$ is in $\operatorname{Match}(t)$. $p$ strictly subsumes $p'$ ($p > p'$) if $p \ge p'$ and $p \ne p'$. $p < p'$ iff $p' > p$.
定义 4.3。令 $p$ 和 $p'$ 为 $S_v$ 中的模式。如果不存在 $S$ 中的主体树 $t$ 使得 $p$ 和 $p'$ 都在 $\operatorname{Match}(t)$ 中，则称 $p$ 与 $p'$ 不一致（记作 $p \parallel p'$ ）。如果存在 $S$ 中的树 $t_1, t_2, t_3$ ，使得 $p$ 在 $\operatorname{Match}(t_1)$ 中、 $p'$ 不在 $\operatorname{Match}(t_1)$ 中、 $p$ 不在 $\operatorname{Match}(t_2)$ 中、 $p'$ 在 $\operatorname{Match}(t_2)$ 中，且 $p$ 和 $p'$ 都在 $\operatorname{Match}(t_3)$ 中，则称 $p$ 和 $p'$ 相互独立（记作 $p ~ p'$ ）。如果对于 $S$ 中的所有 $t$ ， $p$ 在 $\operatorname{Match}(t)$ 中意味着 $p'$ 在 $\operatorname{Match}(t)$ 中，则称 $p$ 包含 $p'$ （ $p \ge p'$ ）。如果 $p \ge p'$ 且 $p \ne p'$ ，则称 $p$ 严格包含 $p'$ （ $p > p'$ ）。 $p < p'$ 当且仅当 $p' > p$ 。

**Example 4.2.** $a(b, v) \parallel a(c, v)$, since $b$ and $c$ cannot both be matched in the same position. $a(b, v) ~ a(v, c)$, since $a(b, v)$ is in $\operatorname{Match}(a(b, b))$, $a(v, c)$ is not in $\operatorname{Match}(a(b, b))$; $a(b, v)$ is not in $\operatorname{Match}(a(c, c))$, $a(v, c)$ is in $\operatorname{Match}(a(c, c))$; and $a(b, v)$ and $a(v, c)$ are both in $\operatorname{Match}(a(b, c))$. Finally, $a(b, v) > a(v, v)$.
示例 4.2。 $a(b, v) \parallel a(c, v)$ ，因为 $b$ 和 $c$ 不能在同一位置同时匹配。 $a(b, v) ~ a(v, c)$ ，因为 $a(b, v)$ 在 $\operatorname{Match}(a(b, b))$ 中， $a(v, c)$ 不在 $\operatorname{Match}(a(b, b))$ 中； $a(b, v)$ 不在 $\operatorname{Match}(a(c, c))$ 中， $a(v, c)$ 在 $\operatorname{Match}(a(c, c))$ 中；且 $a(b, v)$ 和 $a(v, c)$ 都在 $\operatorname{Match}(a(b, c))$ 中。最后， $a(b, v) > a(v, v)$ 。

**Figure 5.** Independence graph for Example 4.3. The graph has a connected component containing $p_1$, $p_2$, and $p_3$, and three isolated points $p_4$, $p_5$, and $p_6$.
图 5。示例 4.3 的独立图。该图有一个包含 $p_1$ 、 $p_2$ 和 $p_3$ 的连通分量，以及三个孤立点 $p_4$ 、 $p_5$ 和 $p_6$ 。

Given distinct patterns $p$ and $p'$, exactly one of the relations $\parallel $,  $~$ , $>$, and $<$ must hold between $p$ and $p'$. The elementary properties of the three relations are summarized below. Note that in the absence of variables distinct patterns must be inconsistent.
给定不同的模式 $p$ 和 $p'$ ，在 $p$ 和 $p'$ 之间必须且仅能成立 $\parallel $ 、  $~$  、 $>$ 和 $<$ 这四种关系之一。这三种关系的初等性质总结如下。请注意，在没有变量的情况下，不同的模式必然是不一致的。

**Proposition 4.1.** For trees $p_1, p_2, p_3$ in $S_v$:
命题 4.1。对于 $S_v$ 中的树 $p_1, p_2, p_3$ ：

*   (a) $p_1 > p_2$ and $p_2 > p_3$ implies $p_1 > p_3$;
    (a) $p_1 > p_2$ 和 $p_2 > p_3$ 蕴含 $p_1 > p_3$ ；
*   (b) $p_1 \parallel p_2$ iff $p_2 \parallel p_1$;
    (b) $p_1 \parallel p_2$ 当且仅当 $p_2 \parallel p_1$ ；
*   (c) $p_1 ~ p_2$ iff $p_2 ~ p_1$;
    (c) $p_1 ~ p_2$ 当且仅当 $p_2 ~ p_1$ ；
*   (d) $p_1 \parallel p_2$ and $p_3 > p_2$ implies $p_1 \parallel p_3$;
    (d) $p_1 \parallel p_2$ 且 $p_3 > p_2$ 蕴含 $p_1 \parallel p_3$ ；
*   (e) $p_1 ~ p_2$ and $p_2 > p_3$ implies $p_1 ~ p_3$ or $p_1 > p_3$.
    (e) $p_1 ~ p_2$ 且 $p_2 > p_3$ 蕴含 $p_1 ~ p_3$ 或 $p_1 > p_3$ 。

Recall that $M'$ of Example 4.1 is not a match set because $a(b, v)$ subsumes $a(v, v)$. The inclusion of one pattern (e.g., $a(v, v)$) in $M$ may be the consequence of the presence of another pattern which subsumes it (e.g., $a(b, v)$). Therefore, there may be a subset of patterns in $M$ which completely determines $M$. We partition each match set $M$ into a set $M_0$ of pairwise independent trees and a set $M_1$ of trees subsumed by some tree in $M_0$. $M_0$ is called the base of $M$.
回想例 4.1 中的 $M'$ 不是匹配集，因为 $a(b, v)$ 包含 $a(v, v)$ 。一个模式（例如 $a(v, v)$ ）被包含在 $M$ 中，可能是因为存在另一个包含它的模式（例如 $a(b, v)$ ）。因此， $M$ 中可能存在一个完全决定 $M$ 的模式子集。我们将每个匹配集 $M$ 划分为一组两两独立的树集合 $M_0$ ，以及一组被 $M_0$ 中某些树所包含的树集合 $M_1$ 。 $M_0$ 被称为 $M$ 的基（base）。

**Proposition 4.2.** Given a pattern forest $F$ and match set $M$ for $F$, there is a unique partition of $M$ into sets $M_0$ and $M_1$ such that for distinct $p_1, p_2$ in $M_0$, $p_1 ~ p_2$ holds, and for each $p'$ in $M_1$ there is a $p$ in $M_0$ such that $p > p'$.
命题 4.2。给定模式森林 $F$ 以及 $F$ 的匹配集 $M$ ，存在唯一的 $M$ 划分，将其分为集合 $M_0$ 和 $M_1$ ，使得对于 $M_0$ 中不同的 $p_1, p_2$ ， $p_1 ~ p_2$ 成立；且对于 $M_1$ 中的每个 $p'$ ，存在 $M_0$ 中的 $p$ 使得 $p > p'$ 。

Observe that different match sets must have different base sets, owing to Proposition 4.1a. Thus we may represent match sets by their base sets.
注意到，根据命题 4.1a，不同的匹配集必须具有不同的基集。因此，我们可以用匹配集的基集来表示它们。

**Definition 4.4.** Given a pattern forest $F$, the independence graph $G_I$ of $F$ is as follows: The vertices of $G_I$ are distinct trees in $PF$. There is an undirected edge between $p$ and $p'$ iff $p ~ p'$.
定义 4.4。给定模式森林 $F$ ， $F$ 的独立图 $G_I$ 定义如下： $G_I$ 的顶点是 $PF$ 中不同的树。在 $p$ 和 $p'$ 之间存在一条无向边，当且仅当 $p ~ p'$ 。

**Example 4.3.** Consider the pattern forest $F = {p_1, p_2, p_3}$, where $p_1 = a(b(b(v)), v)$, $p_2 = a(b(v), b(v))$, and $p_3 = a(v, b(b(v)))$. There are three additional trees in $PF$: $p_4 = b(b(v))$, $p_5 = b(v)$, and $p_6 = v$. Since the trees $p_1$, $p_2$, $p_3$ are pairwise independent, whereas no other tree pairs are, the independence graph $G_I$ of $F$ is as shown in Figure 5, with a connected component $p_1, p_2, p_3$ and three isolated points.
示例 4.3。考虑模式森林 $F = {p_1, p_2, p_3}$ ，其中 $p_1 = a(b(b(v)), v)$ 、 $p_2 = a(b(v), b(v))$ 和 $p_3 = a(v, b(b(v)))$ 。 $PF$ 中还有三棵额外的树： $p_4 = b(b(v))$ 、 $p_5 = b(v)$ 和 $p_6 = v$ 。由于树 $p_1$ 、 $p_2$ 、 $p_3$ 是两两独立的，而其他树对则不然，因此 $F$ 的独立图 $G_I$ 如图 5 所示，包含一个连通分量 $p_1, p_2, p_3$ 和三个孤立点。

From the independence graph we can derive an upper bound on the number of possible match sets of a given pattern forest.
从独立图（independence graph）中，我们可以推导出给定模式森林（pattern forest）可能匹配集数量的上限。

**Theorem 4.3.** The number of possible match sets of a pattern forest $F$ is at most the number of cliques in the independence graph $G_I$ of $F$, counting all subcliques, including the trivial ones.
定理 4.3。模式森林 $F$ 的可能匹配集数量最多为 $F$ 的独立图 $G_I$ 中的团（clique）数量，包括所有子团以及平凡团（trivial cliques）。

This theorem follows easily from Proposition 4.2. To illustrate it, consider $F$ of Example 4.3. The theorem would limit the number of match sets of $F$ to ten, for $G_I$ has six trivial cliques, three cliques of size 2, and one clique of size 3. We would thus expect six match sets with a base set of a singleton, three match sets with base sets consisting of two trees each, and one match set with a base set of three elements. However, in this example there is no match set with the base ${p_1, p_3}$, since matching both $p_1$ and $p_3$ at the root implies that $p_2$ matches at the root as well. Thus Theorem 4.3 gives an upper bound only. For deriving exact limits we would need to introduce other structural properties and analyze relations between more than two patterns.
该定理很容易从命题 4.2 推导出来。为了说明这一点，请考虑示例 4.3 中的 $F$ 。该定理将 $F$ 的匹配集数量限制为 10 个，因为 $G_I$ 拥有 6 个平凡团、3 个大小为 2 的团和 1 个大小为 3 的团。因此，我们预期会有 6 个基集为单元素的匹配集，3 个基集各包含两棵树的匹配集，以及 1 个基集包含三个元素的匹配集。然而，在此示例中，不存在以 ${p_1, p_3}$ 为基集的匹配集，因为在根节点同时匹配 $p_1$ 和 $p_3$ 意味着 $p_2$ 也会在根节点匹配。因此，定理 4.3 仅给出了一个上限。为了推导精确的限制，我们需要引入其他结构属性，并分析两个以上模式之间的关系。

For certain pattern forests the graphs $G_I$ could be such that the number of cliques grows exponentially with the number of subtrees in $F$ and hence exponentially with the size of $F$. In such cases the number of distinct match sets may also grow exponentially.
对于某些模式森林，图 $G_I$ 可能会使得团的数量随 $F$ 中子树的数量呈指数级增长，从而随 $F$ 的规模呈指数级增长。在这种情况下，不同匹配集的数量也可能呈指数级增长。

**Theorem 4.4.** There are classes of pattern forests for which the number of distinct match sets grows exponentially with the size of the forest.
定理 4.4。存在某些模式森林类，其不同匹配集的数量随森林规模呈指数级增长。

**Proof.** We define a class of balanced binary trees $p_j^i$, $0 \le i$, $0 \le j \le 2^i$, of height $i$, with all interior nodes labeled $a$. In $p_j^i$, all leaves are labeled $v$ except the $j$th leaf from the left, which is labeled $b$. For $j = 0$, all leaves are labeled $v$.
证明。我们定义一类高度为 $i$ 的平衡二叉树 $p_j^i$ , $0 \le i$ , $0 \le j \le 2^i$ ，其所有内部节点均标记为 $a$ 。在 $p_j^i$ 中，除左起第 $j$ 个叶节点标记为 $b$ 外，所有叶节点均标记为 $v$ 。对于 $j = 0$ ，所有叶节点均标记为 $v$ 。

$$
\begin{aligned} p_0^0 &= v,\\ p_1^0 &= b,\\ p_j^{i+1} &= a(p_j^i, p_0^i), && 0 \le j \le 2^i,\\ p_j^{i+1} &= a(p_0^i, p_{j-2^i}^i), && 2^i < j \le 2^{i+1}. \end{aligned}
$$

Define the pattern forest $F_n = {p_i^n | 1 \le i \le 2^n}$. The size of $F_n$ is $O(2^n)$. Furthermore, $p_i^n ~ p_j^n$ for distinct nonzero values of $i$ and $j$. Now consider sets $Q$ of integers between 1 and $2^n$, and define for each such set $Q$ a balanced binary tree $p_Q$ of height $n$ with all interior nodes labeled $a$ and such that the $i$th leaf from the left is labeled $b$ if $i$ is in $Q$, $c$ otherwise. Then $p_i^n$ matches $p_Q$ at the root iff $i$ is in $Q$. There are $2^(2^n)$ such sets $Q$; thus there must be at least as many different match sets.
定义模式森林 $F_n = {p_i^n | 1 \le i \le 2^n}$ 。 $F_n$ 的规模为 $O(2^n)$ 。此外，对于不同的非零值 $i$ 和 $j$ ， $p_i^n ~ p_j^n$ 。现在考虑 1 到 $2^n$ 之间整数的集合 $Q$ ，并为每个此类集合 $Q$ 定义一个高度为 $n$ 的平衡二叉树 $p_Q$ ，其所有内部节点均标记为 $a$ ，且如果 $i$ 在 $Q$ 中，则左起第 $i$ 个叶节点标记为 $b$ ，否则标记为 $c$ 。那么，当且仅当 $i$ 在 $Q$ 中时， $p_i^n$ 在根节点处与 $p_Q$ 匹配。存在 $2^(2^n)$ 个这样的集合 $Q$ ；因此，至少存在同样数量的不同匹配集。

As a consequence of Theorem 4.4, a preprocessing algorithm based on computing tables indexed by match sets to drive the bottom-up matching algorithm must be impractical in certain cases. Since independence among subpatterns in a forest is responsible for a possible exponential growth of the number of match sets, we conclude the section with a necessary condition for independence based on the structure of patterns.
作为定理 4.4 的推论，在某些情况下，基于计算以匹配集为索引的表来驱动自底向上匹配算法的预处理算法必然是不切实际的。由于森林中子模式之间的独立性是导致匹配集数量可能呈指数级增长的原因，我们在本节结束时，根据模式结构给出了独立性的一个必要条件。

**Proposition 4.5.** Let $p$, $p'$ be independent patterns. Then $p$ contains disjoint subtrees $t_1$ and $t_2$ and $p'$ contains disjoint subtrees $t'_1$ and $t'_2$, in corresponding positions, such that $t_1 > t'_1$ and $t'_2 < t_2$.
命题 4.5。设 $p$ , $p'$ 为独立模式。则 $p$ 包含不相交的子树 $t_1$ 和 $t_2$ ，且 $p'$ 在对应位置包含不相交的子树 $t'_1$ 和 $t'_2$ ，使得 $t_1 > t'_1$ 且 $t'_2 < t_2$ 。

**Proof.** Since $v$ and nullary symbols in corresponding positions cannot be independent of other patterns, we may assume that
证明。由于 $v$ 及其对应位置的零元符号不能独立于其他模式，我们可以假设

$$
\begin{aligned} p &= a(p_1, \ldots, p_q),\\ p' &= a(p'_1, \ldots, p'_q). \end{aligned}
$$

The proof is by induction on the height of $p$.
证明对 $p$ 的高度进行归纳。

**Basis.** If $p$ has height 1, then the $p_i$ have height 0, thus are nullary symbols or $v$, and thus, for $1 \le i \le q$, $p_i \ge p'_i$ or $p'_i \ge p_i$. If, for all $i$, $p_i \ge p'_i$ ($p'_i \ge p_i$), then $p \ge p'$ ($p' \ge p$). But $p ~ p'$ by assumption, and thus we can find the required trees among $p_i$ and $p'_i$.
基础。若 $p$ 的高度为 1，则 $p_i$ 的高度为 0，因此是零元符号或 $v$ ，从而对于 $1 \le i \le q$ ，有 $p_i \ge p'_i$ 或 $p'_i \ge p_i$ 。如果对于所有 $i$ ，都有 $p_i \ge p'_i$ ( $p'_i \ge p_i$ )，那么 $p \ge p'$ ( $p' \ge p$ )。但根据假设 $p ~ p'$ ，因此我们可以在 $p_i$ 和 $p'_i$ 中找到所需的树。

**Induction step.** Assume that the proposition holds for all $p$ of height less than $h$, and assume that $p$ has height $h$. Surely $p_i \parallel p'_i$ cannot hold; otherwise $p$ and $p'$ would be inconsistent. If there is some $i$ such that $p_i ~ p'_i$, then apply the induction hypothesis to $p_i$ and $p'_i$. Otherwise, for all $i$, $p_i \ge p'_i$ or $p'_i \ge p_i$, and the argument of the induction basis completes the proof.
归纳步骤。假设该命题对所有高度小于 $h$ 的 $p$ 均成立，并假设 $p$ 的高度为 $h$ 。显然 $p_i \parallel p'_i$ 不可能成立；否则 $p$ 和 $p'$ 将会不一致。如果存在某个 $i$ 使得 $p_i ~ p'_i$ ，则对 $p_i$ 和 $p'_i$ 应用归纳假设。否则，对于所有 $i$ ， $p_i \ge p'_i$ 或 $p'_i \ge p_i$ ，归纳基础的论证即可完成证明。

Note that mutual subsumption, in opposite directions, of disjoint subtrees is necessary but not sufficient for independence, since it does not rule out the possibility that other subtrees are inconsistent. For example, $a(b, v, c)$ and $a(v, b, d)$ are inconsistent, yet there are disjoint subtree pairs satisfying the "only if" condition of Proposition 4.5.
请注意，不相交子树在相反方向上的相互包含是独立性的必要条件，但并非充分条件，因为它并未排除其他子树不一致的可能性。例如， $a(b, v, c)$ 和 $a(v, b, d)$ 是不一致的，但仍存在满足命题 4.5 “仅当”条件的不相交子树对。

Proposition 4.5 is used when testing the restrictions imposed on tree patterns in the next section.
命题 4.5 用于测试下一节中对树模式施加的限制。

We have recently learned that the idea of bottom-up tree pattern matching was discovered independently by Kron [^23]. He calls match sets "batches" and defines the relations $>$, $\parallel $,  $~$  (which he calls "more specific than," "not overlapping," and "intersecting," respectively) equivalently by containment and intersection properties of the sets of $\Sigma$\-terms which two patterns match at the root.
我们最近获悉，自底向上树模式匹配的思想是由 Kron [^23] 独立发现的。他将匹配集称为“批次（batches）”，并根据两个模式在根节点处匹配的 $\Sigma$ 项集的包含和交集性质，等价地定义了关系 $>$ 、 $\parallel $ 、  $~$  （他分别称之为“更具体”、“不重叠”和“相交”）。

He matches patterns in a subject tree using an automaton as well. Instead of using matrices as tables, however, he computes the match set to be assigned to node $n$ with $q$ sons by a subautomaton which, in $q$ transition steps reading the match set codes of the sons, determines the code for the new match set. There is one subautomaton per alphabet symbol. As a result, his match time is $O(subsize)$. One can visualize each subautomaton as a trie encoding of one of our matrices. Depending on the pattern structure, this leads to smaller space requirements in certain cases.
他也同样使用自动机在目标树中进行模式匹配。然而，他并没有将矩阵作为表格使用，而是通过一个子自动机来计算分配给具有 $q$ 个子节点的节点 $n$ 的匹配集。该子自动机通过 $q$ 个转换步骤读取子节点的匹配集代码，从而确定新匹配集的代码。每个字母表符号对应一个子自动机。因此，他的匹配时间为 $O(subsize)$ 。我们可以将每个子自动机想象成我们矩阵之一的字典树（trie）编码。根据模式结构的不同，这在某些情况下可以减少空间需求。

The preprocessing of Kron is essentially the method sketched in the paragraphs following Definition 4.2. Because of Theorem 4.4, this preprocessing takes time exponential in the pattern size in the worst case. As Kron tells us, he was aware of this, but it was not a concern of his research in [^23]. We are going further and analyzing match sets seeking a definition of a subclass of tree patterns with polynomial preprocessing time. We give such a definition in the following section.
Kron 的预处理本质上是定义 4.2 之后段落中所概述的方法。由于定理 4.4 的存在，这种预处理在最坏情况下的耗时与模式大小呈指数关系。正如 Kron 所言，他意识到了这一点，但这并不是他在 [^23] 中研究的重点。我们正在进一步分析匹配集，试图定义一类具有多项式预处理时间的树模式子集。我们将在下一节中给出这样一个定义。

Preprocessing in Kron's sense has been used in practical situations by Wilhelm [^10]. Since this work seems to accomplish practically viable preprocessing times, we conclude that the exponential worst case of bottom-up matching does not arise frequently in these applications.
Wilhelm [^10] 已在实际情况中使用了 Kron 意义上的预处理。由于这项工作似乎实现了实际可行的预处理时间，我们得出结论：自底向上匹配的最坏指数情况在这些应用中并不经常出现。

## 5\. Simple Pattern Forests
5\. 简单模式森林

Because of the exponential growth of the number of match sets for certain pattern forests (Theorem 4.4), we wish to restrict patterns when generating tables to drive the bottom-up matching algorithm of Section 3. Theorem 4.3 suggests disallowing independence among pattern subtrees. This restriction is not as drastic as it might seem and has not seriously hindered us when generating interpreters for LISP, LUCID, and the Combinator Calculus using these techniques [^14].
由于某些模式森林的匹配集数量呈指数级增长（定理 4.4），我们希望在生成驱动第 3 节自底向上匹配算法的表时，对模式进行限制。定理 4.3 建议禁止模式子树之间的独立性。这种限制并不像看起来那么剧烈，并且在使用这些技术为 LISP、LUCID 和组合子演算（Combinator Calculus）生成解释器时，并未对我们造成严重阻碍 [^14]。

**Definition 5.1.** A pattern forest $F$ is simple if it contains no independent subtrees.
定义 5.1。如果一个模式森林 $F$ 不包含独立的子树，则称其为简单模式森林。

For simple forests, the independence graph has no edges; hence, by Theorem 4.3, the number of distinct match sets is at most the size of the forest. Furthermore, simple forests have a number of useful properties which can be exploited in the design of efficient matching algorithms.
对于简单森林，其独立图没有边；因此，根据定理 4.3，不同匹配集的数量最多为森林的大小。此外，简单森林具有许多有用的特性，可以在设计高效匹配算法时加以利用。

**Definition 5.2.** If $F$ is a pattern forest, and $p$, $p'$ are subpatterns in $PF$, then $p$ immediately subsumes $p'$, written $p >_i p'$, iff $p > p'$ and there is no other subpattern $p''$ in $PF$ such that $p > p''$ and $p'' > p'$. Immediate subsumption is the transitive reduction of subsumption on the set of all subpatterns of $F$.
定义 5.2。如果 $F$ 是一个模式森林，且 $p$ 、 $p'$ 是 $PF$ 中的子模式，那么当且仅当 $p > p'$ 且 $PF$ 中不存在其他子模式 $p''$ 满足 $p > p''$ 和 $p'' > p'$ 时，称 $p$ 立即包含（immediately subsumes） $p'$ ，记作 $p >_i p'$ 。立即包含是 $F$ 所有子模式集合上包含关系的传递归约（transitive reduction）。

**Definition 5.3.** The immediate subsumption graph $G_S$ of the forest $F$ has as vertices all distinct subpatterns in $F$. There is a directed edge from $p$ to $p'$ iff $p >_i p'$. In general, $G_S$ is a directed acyclic graph with $v$ as the only leaf.
定义 5.3。森林 $F$ 的直接包含图 $G_S$ 以 $F$ 中所有不同的子模式作为顶点。当且仅当 $p >_i p'$ 时，存在一条从 $p$ 到 $p'$ 的有向边。通常情况下， $G_S$ 是一个有向无环图，且以 $v$ 为唯一的叶节点。

**Figure 6.** The immediate subsumption graph of $F$.
图 6. $F$ 的直接包含图。

**Lemma 5.1.** The immediate subsumption graph $G_S$ of a simple forest $F$ is an inverted tree with $v$ as root.
引理 5.1。简单森林 $F$ 的直接包含图 $G_S$ 是一棵以 $v$ 为根的倒置树。

**Proof.** Let $p$, $p'$, and $p''$ be distinct subtrees in $F$, and assume that $p$ subsumes both $p'$ and $p''$, but neither $p' > p''$ nor $p'' > p'$. Since $p$ subsumes both trees, $p' \parallel p''$ is impossible (Proposition 4.1d); hence $p'$ and $p''$ must be independent. But then $F$ cannot be simple. Hence either $p' > p''$ or $p'' > p'$.
证明。设 $p$ 、 $p'$ 和 $p''$ 是 $F$ 中不同的子树，并假设 $p$ 包含 $p'$ 和 $p''$ ，但不包含 $p' > p''$ 或 $p'' > p'$ 。由于 $p$ 包含这两棵树， $p' \parallel p''$ 是不可能的（命题 4.1d）；因此 $p'$ 和 $p''$ 必须是独立的。但这样一来 $F$ 就不可能是简单的。因此，要么 $p' > p''$ ，要么 $p'' > p'$ 。

Observe that for simple forests, the base set $M_0$ of any match set must be a singleton. Using Lemma 5.1 and Proposition 4.2, we thus easily obtain:
观察到对于简单森林，任何匹配集的基集 $M_0$ 必须是单元素集合。利用引理 5.1 和命题 4.2，我们很容易得出：

**Theorem 5.2.** Let $F$ be a simple forest and $M$ any match set for $F$ with base set ${p}$. Then $M$ consists precisely of the trees encountered on the path from $p$ to $v$ in $G_S$.
定理 5.2。设 $F$ 为一个简单森林， $M$ 为 $F$ 的任意匹配集，其基集为 ${p}$ 。那么 $M$ 恰好由在 $G_S$ 中从 $p$ 到 $v$ 的路径上所遇到的树组成。

This theorem is the central result for simple forests. It frees us from having to construct explicitly the individual match sets, for $G_S$ provides them at once along with their structure and interrelation. We conclude the section with an example illustrating Theorem 5.2, and a discussion of the relationship between $G_S$ and the failure function $f$ constructed in the algorithm for string pattern matching in [^1][^21].
该定理是关于简单森林的核心结论。它使我们无需显式地构造单个匹配集，因为 $G_S$ 直接提供了这些匹配集及其结构和相互关系。在本节末尾，我们通过一个例子来说明定理 5.2，并讨论 $G_S$ 与 [^1][^21] 中字符串模式匹配算法所构造的失效函数 $f$ 之间的关系。

**Example 5.1.** The pattern forest $F = {a(a(v, v), b), a(b, v)}$ is simple, since there are no independent trees or subtrees. Its immediate subsumption relation is
示例 5.1。模式森林 $F = {a(a(v, v), b), a(b, v)}$ 是简单的，因为不存在独立的树或子树。其直接包含关系为

$$
\begin{aligned} b &>_i v, & a(v, v) &>_i v,\\ a(b, v) &>_i a(v, v), & a(a(v, v), b) &>_i a(v, v). \end{aligned}
$$

which has the graph $G_S$ shown in Figure 6. From this graph we then obtain as possible match sets the five sets of Example 3.1:
其图 $G_S$ 如图 6 所示。从该图中，我们随后可以得到例 3.1 中的五个集合作为可能的匹配集：

$$
\begin{aligned} &\{v\}\\ &\{b, v\}\\ &\{a(v, v), v\}\\ &\{a(b, v), a(v, v), v\}\\ &\{a(a(v, v), b), a(v, v), v\} \end{aligned}
$$

Note the correspondence of these sets to the paths in $G_S$.
请注意这些集合与 $G_S$ 中路径的对应关系。

There is a connection between the immediate subsumption graph $G_S$ and the failure function $f$ used in string-pattern-matching algorithms in [^1][^21]. This connection is observed by visualizing a string pattern $a_1a_2\ldots a_m$ as the nonbranching tree $a_m(\ldots a_2(a_1(v))\ldots)$. Note the reversal of the character sequence. The addition of $v$ as a leaf permits us to conceptualize the $a_i$ as symbols of arity 1 and permits sliding the nonbranching tree in the subject. Matching this pattern in the subject $b_1b_2\ldots b_n$ is now equivalent to matching the nonbranching tree pattern in the tree $b_n(\ldots b_2(b_1(c))\ldots)$, where $c$ is a new nullary symbol. Having translated the string-matching problem into a tree-matching problem in this way, we now observe that $G_S$ is just the graph of the failure function $f$ constructed for the original string problem by the algorithms in [^1][^21]. To observe this, note that a subtree corresponds to a pattern prefix, and that $p > p'$ iff $p'$ is a pattern prefix which matches, as suffix, in the pattern prefix $p$. Hence $p >_i p'$ iff $p'$ is the longest proper prefix of $p$ which matches, as suffix, in the prefix $p$, which is just the definition of the failure function.
直接包含图 $G_S$ 与 [^1][^21] 中字符串模式匹配算法所使用的失效函数 $f$ 之间存在联系。通过将字符串模式 $a_1a_2\ldots a_m$ 可视化为非分支树 $a_m(\ldots a_2(a_1(v))\ldots)$ ，可以观察到这种联系。注意字符序列的逆转。添加 $v$ 作为叶节点使我们能够将 $a_i$ 概念化为元数为 1 的符号，并允许在主体中滑动该非分支树。在主体 $b_1b_2\ldots b_n$ 中匹配此模式现在等同于在树 $b_n(\ldots b_2(b_1(c))\ldots)$ 中匹配该非分支树模式，其中 $c$ 是一个新的零元符号。通过这种方式将字符串匹配问题转化为树匹配问题后，我们现在观察到 $G_S$ 正是针对原始字符串问题通过 [^1][^21] 中的算法构造的失效函数 $f$ 的图。为了观察这一点，请注意子树对应于模式前缀，且 $p > p'$ 当且仅当 $p'$ 是一个模式前缀，该前缀作为后缀匹配于模式前缀 $p$ 中。因此， $p >_i p'$ 当且仅当 $p'$ 是 $p$ 的最长真前缀，且该前缀作为后缀匹配于前缀 $p$ 中，这正是失效函数的定义。

Note also that because of Proposition 4.5, pattern forests derived from string patterns must be simple, because nonbranching trees cannot have disjoint subtrees. Hence there is no counterpart in string matching to the exponential explosion of match sets, which can occur for nonsimple forests in tree matching.
还请注意，根据命题 4.5，源自字符串模式的模式森林必须是简单的，因为非分支树不可能拥有不相交的子树。因此，在字符串匹配中，不存在与树匹配中非简单森林可能出现的匹配集指数级爆炸相对应的情况。

## 6\. Table Construction for Simple Forests
6\. 简单森林的表格构建

For a simple pattern forest $F$, the tables to drive the bottom-up algorithm of Section 3 may be constructed in two steps. First, construct the subsumption graph $\bar{G}_S$ whose vertices are the trees in $PF$. $\bar{G}_S$ has a directed edge from $p$ to $p'$ iff $p \ge p'$. Observe that this is equivalent to finding all match sets which can occur when matching in any subject. Then, for each alphabet symbol $a$ of arity $m$, we use $G_S$ to construct a table $T_a$ such that $T_a[p_1, \ldots, p_m]$ is the match-set code which should be assigned to any node labeled $a$ at whose sons we have assigned the match-set codes $p_1$ to $p_m$ from left to right, respectively.
对于简单模式森林 $F$ ，用于驱动第 3 节自底向上算法的表可以分两步构造。首先，构造包含图 $\bar{G}_S$ ，其顶点是 $PF$ 中的树。 $\bar{G}_S$ 具有从 $p$ 到 $p'$ 的有向边，当且仅当 $p \ge p'$ 。观察到这等同于找到在任何主体中匹配时可能出现的所有匹配集。然后，对于元数为 $m$ 的每个字母表符号 $a$ ，我们使用 $G_S$ 构造一个表 $T_a$ ，使得 $T_a[p_1, \ldots, p_m]$ 是应分配给任何标记为 $a$ 的节点的匹配集代码，在该节点处，我们已分别为其子节点从左到右分配了匹配集代码 $p_1$ 到 $p_m$ 。

We find it convenient to represent a match set $M$ by its base set tree, that is, by the largest (in the sense of $>$) tree in $M$. This is a reasonable choice since, by Proposition 4.2 and Theorem 5.2, the largest tree in $M$ completely determines $M$. The advantage of this coding is that we can now define the entry $T_a[p_1, \ldots, p_m]$ as the largest tree in $PF$ subsumed by $a(p_1, \ldots, p_m)$, because of observation (2) below. Note that the tree $a(p_1, \ldots, p_m)$ need not occur in $PF$.
我们发现，用匹配集 $M$ 的基集树（即 $>$ 中最大的树）来表示该匹配集非常方便。这是一个合理的选择，因为根据命题 4.2 和定理 5.2， $M$ 中最大的树完全决定了 $M$ 。这种编码方式的优势在于，基于下文的观察 (2)，我们现在可以将项 $T_a[p_1, \ldots, p_m]$ 定义为 $PF$ 中被 $a(p_1, \ldots, p_m)$ 所包含的最大树。请注意，树 $a(p_1, \ldots, p_m)$ 不一定出现在 $PF$ 中。

To construct $\bar{G}_S$, observe that for distinct patterns $p$, $p'$:
为了构建 $\bar{G}_S$ ，观察对于不同的模式 $p$ 和 $p'$ ：

1.  If $p > p'$, then $height(p) \ge height(p')$.
    如果 $p > p'$ ，那么 $height(p) \ge height(p')$ 。
2.  Let $p = a(p_1, \ldots, p_m)$. Then $p > p'$ iff either $p' = v$ or $p' = a(p'_1, \ldots, p'_m)$, where $p_j \ge p'_j$ for $1 \le j \le m$.
    设 $p = a(p_1, \ldots, p_m)$ 。那么 $p > p'$ 当且仅当 $p' = v$ 或 $p' = a(p'_1, \ldots, p'_m)$ ，其中对于 $1 \le j \le m$ 有 $p_j \ge p'_j$ 。

So we may process patterns in order of increasing height and compare each pattern to all patterns of no greater height using observation (2). Since the subpatterns $p_j$ and $p'_j$ in (2) above are of strictly smaller height than $p$ and $p'$, respectively, $p_j \ge p'_j$ has already been checked by the time $p$ is compared to $p'$.
因此，我们可以按照高度递增的顺序处理模式，并利用观察结果 (2) 将每个模式与所有高度不大于它的模式进行比较。由于上述 (2) 中的子模式 $p_j$ 和 $p'_j$ 的高度分别严格小于 $p$ 和 $p'$ ，因此在将 $p$ 与 $p'$ 进行比较时， $p_j \ge p'_j$ 已经完成了检查。

**Algorithm A
算法 A**

Input: Simple pattern forest $F$.
输入：简单模式森林 $F$ 。
Output: Subsumption graph $\bar{G}_S$ for $F$.
输出： $F$ 的包含图 $\bar{G}_S$ 。

```
1. List the trees in PF by increasing height.
2. Initialize \bar{G}_S to the graph with vertices PF and no edges.
3. For each p = a(p_1, ..., p_m), m >= 0, of height h,
   by increasing order of height, do:
4.   For each p' in PF of height <= h do:
5.     If p' = v or
          p' = a(p'_1, ..., p'_m) where, for 1 <= j <= m,
          p_j -> p'_j is in \bar{G}_S,
       then:
6.       Add p -> p' to \bar{G}_S.
```

For the analysis of Algorithm A, observe that step 1 requires $O(patsize)$ time using bucketsort. Steps 3-6 require $O(patsize^2 * rank)$ steps, assuming that $\bar{G}_S$ is stored as an adjacency matrix, so that checking whether $p_i -> p'_i$ requires constant time. The space complexity is dominated by the $O(patsize^2)$ adjacency matrix. Thus Algorithm A requires $O(patsize^2 * rank)$ steps and $O(patsize^2)$ space.
对于算法 A 的分析，观察到步骤 1 使用桶排序需要 $O(patsize)$ 时间。假设 $\bar{G}_S$ 存储为邻接矩阵，使得检查 $p_i -> p'_i$ 是否成立需要常数时间，那么步骤 3-6 需要 $O(patsize^2 * rank)$ 步。空间复杂度主要由 $O(patsize^2)$ 邻接矩阵决定。因此，算法 A 需要 $O(patsize^2 * rank)$ 步和 $O(patsize^2)$ 空间。

To generate the table $T_a$, recall that for the $m$\-ary symbol $a$ and trees $p_1, \ldots, p_m$ in $PF$, $T_a[p_1, \ldots, p_m] = p$, where $p$ is the largest (in the sense of $>$) tree in $PF$ such that $a(p_1, \ldots, p_m) \ge p$. This can be seen as follows. If $a(p_1, \ldots, p_m) \ge t$, then either $t = v$ or $t = a(p'_1, \ldots, p'_m)$ and, for $1 \le i \le m$, $p_i \ge p'_i$. Then the set
要生成表格 $T_a$ ，回想一下，对于 $m$ 元符号 $a$ 和 $PF$ 中的树 $p_1, \ldots, p_m$ ， $T_a[p_1, \ldots, p_m] = p$ ，其中 $p$ 是 $PF$ 中最大的（在 $>$ 的意义下）满足 $a(p_1, \ldots, p_m) \ge p$ 的树。这可以从以下方面看出。如果 $a(p_1, \ldots, p_m) \ge t$ ，那么要么 $t = v$ ，要么 $t = a(p'_1, \ldots, p'_m)$ 且对于 $1 \le i \le m$ ，有 $p_i \ge p'_i$ 。那么集合

$$
M = \{t \in PF \mid a(p_1, \ldots, p_m) \ge t\}
$$

is precisely the match set which should be coded by the entry $T_a[p_1, \ldots, p_m]$, assuming $p_i$ codes the match set with base set tree $p_i$. Recall that by Lemma 5.1 subsumption induces a total order on the elements of $M$; hence the largest tree $p$ in $PF$ subsumed by $a(p_1, \ldots, p_m)$ is precisely the base set tree of $M$ and thus the code which should be assigned to $T_a[p_1, \ldots, p_m]$.
恰好是应由条目 $T_a[p_1, \ldots, p_m]$ 编码的匹配集，假设 $p_i$ 编码了以树 $p_i$ 为基集的匹配集。回想一下，根据引理 5.1，包含关系在 $M$ 的元素上诱导了一个全序；因此，被 $a(p_1, \ldots, p_m)$ 包含的 $PF$ 中最大的树 $p$ 恰好是 $M$ 的基集树，因此也就是应分配给 $T_a[p_1, \ldots, p_m]$ 的代码。

Now observe that by (2), $a(p_1, \ldots, p_m) \ge p$ is easily testable from $\bar{G}_S$. Furthermore, if we process the patterns in $PF$ in increasing order of subsumption and for each $p$ in $PF$ assign $p$ to all of the entries $T_a[p_1, \ldots, p_m]$ such that $a(p_1, \ldots, p_m) \ge p$, then the last assignment made to the entry will be the maximal subsumed $p$ in $PF$. Thus, if we write each $p$ into the appropriate table positions when $p$ is processed, the final values in the table are the correct ones.
现在观察到，通过 (2)， $a(p_1, \ldots, p_m) \ge p$ 很容易从 $\bar{G}_S$ 测试。此外，如果我们按照包含关系的递增顺序处理 $PF$ 中的模式，并且对于 $PF$ 中的每个 $p$ ，将 $p$ 分配给所有满足 $a(p_1, \ldots, p_m) \ge p$ 的条目 $T_a[p_1, \ldots, p_m]$ ，那么对该条目进行的最后一次分配将是 $PF$ 中最大的被包含树 $p$ 。因此，如果在处理 $p$ 时将每个 $p$ 写入适当的表格位置，则表格中的最终值就是正确的。

**Algorithm B
算法 B**

Input: $\bar{G}_S$ for a simple pattern forest $F$.
输入：简单模式森林 $F$ 的 $\bar{G}_S$ 。
Output: Tables to drive the bottom-up matching algorithm. $T_a[p_1, \ldots, p_m]$ will contain the largest (under subsumption) tree in $PF$ which is subsumed by $a(p_1, \ldots, p_m)$.
输出：用于驱动自下而上匹配算法的表。 $T_a[p_1, \ldots, p_m]$ 将包含 $PF$ 中被 $a(p_1, \ldots, p_m)$ 包含的最大（在包含关系下）树。

```
1. List PF in increasing order of subsumption by performing a topological sort
   on \bar{G}_S.
2. Initialize all entries in all tables T_a to v.
3. For each pattern p = a(p_1, ..., p_m) by increasing order of subsumption do:
4.   For each m-tuple (p'_1, ..., p'_m) such that,
     for 1 <= j <= m, p'_j >= p_j do:
5.     T_a[p'_1, ..., p'_m] := p.
```

The table for the symbol $a$ of arity $q$ has $patsize^q$ entries. Thus Algorithm B constructs no more than $patsize^rank * sym$ entries. When a tree $p$ is assigned to an entry in $T_a$, then $p$ belongs to the match set which should be coded by this entry. Thus the number of repeated assignments to each entry cannot exceed the size of the largest match set, that is, the height of $G_S$. Thus at most $patsize^rank * sym * ht$ assignments are done in step 5.
元数为 $q$ 的符号 $a$ 的表具有 $patsize^q$ 个条目。因此，算法 B 构造的条目不超过 $patsize^rank * sym$ 个。当树 $p$ 被分配给 $T_a$ 中的一个条目时， $p$ 属于应由该条目编码的匹配集。因此，对每个条目的重复分配次数不能超过最大匹配集的大小，即 $G_S$ 的高度。因此，在第 5 步中最多进行 $patsize^rank * sym * ht$ 次分配。

Note that $p'_j$ ranges over those trees in $PF$ such that $p'_j \ge p_j$. Hence we can find the necessary tuples easily from the adjacency matrix of $\bar{G}_S$. In an implementation of this algorithm the patterns in $PF$ are numbered, and the tables $T_a$ are indexed by these numbers. We summarize the complexity of preprocessing patterns in simple forests by the following.
注意 $p'_j$ 的范围是 $PF$ 中满足 $p'_j \ge p_j$ 的那些树。因此，我们可以很容易地从 $\bar{G}_S$ 的邻接矩阵中找到必要的元组。在该算法的实现中， $PF$ 中的模式被编号，而表 $T_a$ 则由这些编号索引。我们将简单森林中预处理模式的复杂度总结如下。

**Theorem 6.1.** We can construct tables to drive the bottom-up matching algorithm in the case of simple pattern forest in
定理 6.1。在简单模式森林的情况下，我们可以构造用于驱动自下而上匹配算法的表，其时间复杂度为

$$
O(\mathit{patsize}^2 \cdot \mathit{rank} + \mathit{patsize}^{\mathit{rank}} \cdot \mathit{ht} \cdot \mathit{sym})
$$

time and
时间与

$$
O(\mathit{patsize}^2 + \mathit{sym} + \mathit{patsize}^{\mathit{rank}})
$$

space.
空间。

Note that it is easy to test whether a pattern forest is simple. Using Proposition 4.5, it suffices to test, in step 5 of Algorithm A, whether $p$ and $p'$ contain two immediate subtrees in corresponding positions which subsume each other in opposite directions. If such a pair exists, then the pattern forest is not simple.
注意，测试一个模式森林是否为简单的（simple）非常容易。根据命题 4.5，在算法 A 的第 5 步中，只需测试 $p$ 和 $p'$ 是否在对应位置包含两个相互包含（subsume）的直接子树。如果存在这样的一对子树，则该模式森林不是简单的。

**Table I. Table $T_a$ generated for the symbol $a$.
表 I. 为符号 $a$ 生成的表 $T_a$ 。**

| Left subtree match左子树匹配 | vvv | bbb | a(v,v)a(v, v)a(v,v) | a(b,v)a(b, v)a(b,v) | a(a(v,v),b)a(a(v, v), b)a(a(v,v),b) |
| --- | --- | --- | --- | --- | --- |
| vvv | a(v,v)a(v, v)a(v,v) | a(v,v)a(v, v)a(v,v) | a(v,v)a(v, v)a(v,v) | a(v,v)a(v, v)a(v,v) | a(v,v)a(v, v)a(v,v) |
| bbb | a(b,v)a(b, v)a(b,v) | a(b,v)a(b, v)a(b,v) | a(b,v)a(b, v)a(b,v) | a(b,v)a(b, v)a(b,v) | a(b,v)a(b, v)a(b,v) |
| a(v,v)a(v, v)a(v,v) | a(v,v)a(v, v)a(v,v) | a(a(v,v),b)a(a(v, v), b)a(a(v,v),b) | a(v,v)a(v, v)a(v,v) | a(v,v)a(v, v)a(v,v) | a(v,v)a(v, v)a(v,v) |
| a(b,v)a(b, v)a(b,v) | a(v,v)a(v, v)a(v,v) | a(a(v,v),b)a(a(v, v), b)a(a(v,v),b) | a(v,v)a(v, v)a(v,v) | a(v,v)a(v, v)a(v,v) | a(v,v)a(v, v)a(v,v) |
| a(a(v,v),b)a(a(v, v), b)a(a(v,v),b) | a(v,v)a(v, v)a(v,v) | a(a(v,v),b)a(a(v, v), b)a(a(v,v),b) | a(v,v)a(v, v)a(v,v) | a(v,v)a(v, v)a(v,v) | a(v,v)a(v, v)a(v,v) |

**Example 6.1.** We illustrate Algorithm B with the table $T_a$ generated for the symbol $a$, given the pattern forest of Example 5.1. The table is essentially that of Example 3.1; however, for readability we represent entries and index values by trees, rather than enumerating them.
示例 6.1。我们以针对符号 $a$ 生成的表 $T_a$ 为例来阐述算法 B，给定示例 5.1 中的模式森林。该表本质上与示例 3.1 中的表相同；然而，为了提高可读性，我们用树来表示表项和索引值，而不是对它们进行枚举。

In this example, all table entries are assigned by step 5, so none of them is $v$. Consider $p = a(a(v, v), b)$ in the traversal of step 3. The $m$\-tuples of steps 4 and 5 now range over the sets $p'_1$ in ${a(v, v), a(a(v, v), b), a(b, v)}$, since $a(a(v, v), b)$ and $a(b, v)$ are the two trees subsuming $a(v, v)$, and $p'_2$ in ${b}$, since there is no other tree subsuming $b$. So $a(a(v, v), b)$ is entered in $T_a[a(v, v), b]$, $T_a[a(a(v, v), b), b]$, and $T_a[a(b, v), b]$. The entry $T_a[a(v, v), b]$ had already been assigned the smaller pattern $a(v, v)$, since $a(v, v) > v$ and $b > v$, but this entry is wiped out by $a(a(v, v), b)$ at this time. Table I shows the table $T_a$.
在此示例中，所有表项均由步骤 5 分配，因此其中没有一个是 $v$ 。考虑步骤 3 遍历中的 $p = a(a(v, v), b)$ 。步骤 4 和 5 的 $m$ 元组现在的范围涵盖了 ${a(v, v), a(a(v, v), b), a(b, v)}$ 中的集合 $p'_1$ （因为 $a(a(v, v), b)$ 和 $a(b, v)$ 是包含 $a(v, v)$ 的两棵树），以及 ${b}$ 中的 $p'_2$ （因为没有其他树包含 $b$ ）。因此， $a(a(v, v), b)$ 被填入 $T_a[a(v, v), b]$ 、 $T_a[a(a(v, v), b), b]$ 和 $T_a[a(b, v), b]$ 中。表项 $T_a[a(v, v), b]$ 之前已被分配了较小的模式 $a(v, v)$ （因为 $a(v, v) > v$ 和 $b > v$ ），但该表项此时被 $a(a(v, v), b)$ 覆盖。表 I 显示了表 $T_a$ 。

Clearly Algorithm B constitutes the bottleneck of preprocessing, both in space and in time requirements. Often the situation can be improved by introducing one or more pairing functions, thereby reducing $rank$ to 2. Although pairing is always possible, it need not preserve simplicity of the forest and is thus of limited value.
显然，算法 B 构成了预处理在空间和时间需求方面的瓶颈。通常可以通过引入一个或多个配对函数来改善这种情况，从而将 $rank$ 减少到 2。虽然配对总是可行的，但它不一定能保持森林的简单性，因此价值有限。

**Example 6.2.** Consider the pattern forest ${a(b, v, c), a(v, b, d), a(e, c, v)}$. All subtrees other than $v$ are pairwise inconsistent, and thus the forest is simple. Introducing a pairing function, no matter which subtrees are paired, will introduce independence. For example, pairing the first and second subtree results in a new forest ${a'(pair(b, v), c), a'(pair(v, b), d), a'(pair(e, c), v)}$ in which $pair(b, v)$ and $pair(v, b)$ are independent subtrees.
例 6.2. 考虑模式森林 ${a(b, v, c), a(v, b, d), a(e, c, v)}$ 。除 $v$ 之外的所有子树都是两两不一致的，因此该森林是简单的。引入配对函数，无论哪两个子树配对，都会引入独立性。例如，将第一个和第二个子树配对会得到一个新的森林 ${a'(pair(b, v), c), a'(pair(v, b), d), a'(pair(e, c), v)}$ ，其中 $pair(b, v)$ 和 $pair(v, b)$ 是独立的子树。

There is a different approach to speeding up preprocessing. Recall that $G_S$ generalizes the failure function of string matching. We suspect that there is an efficient bottom-up matching algorithm using $G_S$ directly, without any tables. So far we have only achieved a running time of
还有一种不同的方法可以加速预处理。回想一下， $G_S$ 推广了字符串匹配的失效函数。我们怀疑存在一种直接使用 $G_S$ 而不需要任何表格的高效自底向上匹配算法。到目前为止，我们通过这种方法仅实现了

$$
O(\mathit{subsize} \cdot \mathit{patsize} \cdot \mathit{ht})
$$

by this approach, which is inferior to the naive method.
的运行时间，这劣于天真方法（naive method）。

## 7\. Faster Preprocessing for Binary Simple Forests
7\. 二叉简单森林的更快速预处理

Algorithm A is quadratic in $patsize$ since it constructs $\bar{G}_S$, the transitive closure of $G_S$, rather than $G_S$. It seems there should be an algorithm for computing $G_S$ for simple pattern forests which requires $O(patsize)$ steps only. So far, we have not found an algorithm this efficient, but in the special case of binary simple pattern forests we can construct $G_S$ in $O(patsize * ht^2)$ steps. Here $ht$ may be as large as $patsize$, but it is usually much smaller. Given the algorithm for computing $G_S$, it is then possible to adapt it to do the pattern matching as well, bypassing the expensive step of table generation. We sketch the idea of this algorithm next.
算法 A 对 $patsize$ 是二次方的，因为它构建的是 $G_S$ 的传递闭包 $\bar{G}_S$ ，而不是 $G_S$ 。似乎应该存在一种算法，在计算简单模式森林的 $G_S$ 时仅需 $O(patsize)$ 步。到目前为止，我们还没有发现如此高效的算法，但在二叉简单模式森林的特殊情况下，我们可以在 $O(patsize * ht^2)$ 步内构建 $G_S$ 。这里 $ht$ 可能大至 $patsize$ ，但通常要小得多。有了计算 $G_S$ 的算法后，就可以将其改写以进行模式匹配，从而绕过代价高昂的表生成步骤。接下来我们简述该算法的思路。

**Figure 7.** Path-string representation for $a(a(b, v), c)$.
图 7. $a(a(b, v), c)$ 的路径字符串表示。

Recall that in a simple forest $F$, for each subpattern $p$ in $PF$ there is exactly one largest subsumed subpattern $p'$ in $PF$, except when $p = v$. Let $f(p)$ denote this tree $p'$, that is, the tree immediately subsumed by $p$. Denote the $i$th iterate of $f$ by $f^i(p)$, $0 \le i$, where
回想一下，在简单森林 $F$ 中，对于 $PF$ 中的每个子模式 $p$ ，在 $PF$ 中恰好有一个最大的被包含子模式 $p'$ ，除非 $p = v$ 。令 $f(p)$ 表示这棵树 $p'$ ，即紧接被 $p$ 包含的树。用 $f^i(p)$ 表示 $f$ 的第 $i$ 次迭代，其中 $0 \le i$ ，即

$$
\begin{aligned} f^0(p) &= p,\\ f^{i+1}(p) &= f(f^i(p)). \end{aligned}
$$

Note that $G_S$ is the graph of the function $f$.
注意 $G_S$ 是函数 $f$ 的图。

Consider computing $f(p)$, where the root of $p$ is a binary symbol, that is, $p = a(p_1, p_2)$. We should examine trees of the form $a(f^i(p_1), f^j(p_2))$, $i + j > 0$, as possible candidates for $f(p)$. For this purpose we will maintain sets $S(a, p_1)$, where $a$ is in $\Sigma$ and $p_1$ is a pattern subtree. Each set contains pairs $(p_2, p)$ of subpatterns. The pair $(p_2, p)$ is in $S(a, p_1)$ iff $p = a(p_1, p_2)$ is in $PF$. In computing $f(p)$ we now probe in the sets $S(a, p_1)$, $S(a, f(p_1))$, $S(a, f^2(p_1))$, ... for pairs whose first component is $p_2$, $f(p_2)$, etc. The first such pair found (other than the pair $(p_2, p)$ in $S(a, p_1)$) must be $f(p)$, since $F$ is a simple forest. We make at most $O(ht^2)$ probes, since $f^ht(t) = v$ for any subpattern.
考虑计算 $f(p)$ ，其中 $p$ 的根是一个二元符号，即 $p = a(p_1, p_2)$ 。我们应该检查形式为 $a(f^i(p_1), f^j(p_2))$ ， $i + j > 0$ 的树，作为 $f(p)$ 的可能候选。为此，我们将维护集合 $S(a, p_1)$ ，其中 $a$ 在 $\Sigma$ 中，且 $p_1$ 是一个模式子树。每个集合包含子模式对 $(p_2, p)$ 。当且仅当 $p = a(p_1, p_2)$ 在 $PF$ 中时，对 $(p_2, p)$ 在 $S(a, p_1)$ 中。在计算 $f(p)$ 时，我们现在在集合 $S(a, p_1)$ ， $S(a, f(p_1))$ ， $S(a, f^2(p_1))$ ，... 中探测其第一个分量为 $p_2$ ， $f(p_2)$ 等的对。找到的第一个这样的对（除了 $S(a, p_1)$ 中的对 $(p_2, p)$ ）必须是 $f(p)$ ，因为 $F$ 是一个简单森林。我们最多进行 $O(ht^2)$ 次探测，因为对于任何子模式， $f^ht(t) = v$ 。

We can make a single probe efficiently by representing the set $S(a, p_1)$ by an array in which the second component of a pair is stored as the element indexed by the first component. In order to avoid an $O(patsize^2)$ overhead for initializing all vectors, we use the constant time array initialization of [^2], Ex. 2.12. The running time of the algorithm is thus $O(patsize * ht^2)$.
我们可以通过用数组表示集合 $S(a, p_1)$ 来高效地进行单次探测，其中对的第二个分量存储为以第一个分量为索引的元素。为了避免初始化所有向量带来的 $O(patsize^2)$ 开销，我们使用 [^2], Ex. 2.12 中的常数时间数组初始化方法。因此，该算法的运行时间为 $O(patsize * ht^2)$ 。

Observe that the algorithm can be adapted to do the matching using the sets $S(a, p_1)$ without using the table generation (Algorithm B). This leads to a matching algorithm which requires at most $O(subsize * ht^2)$ steps.
观察到，该算法可以调整为使用集合 $S(a, p_1)$ 进行匹配，而不使用表格生成（算法 B）。这产生了一个最多需要 $O(subsize * ht^2)$ 步的匹配算法。

## 8\. Top-Down Matching Algorithm
8\. 自顶向下匹配算法

Like the bottom-up matching algorithm, our top-down matching algorithm is related to the Knuth-Morris-Pratt string-matching algorithm. Instead of generalizing string matching, however, the top-down approach reduces tree matching to string matching. The top-down method has slower matching time than the bottom-up, but better preprocessing time.
与自底向上匹配算法类似，我们的自顶向下匹配算法也与 Knuth-Morris-Pratt 字符串匹配算法相关。然而，自顶向下的方法并非对字符串匹配进行泛化，而是将树匹配简化为字符串匹配。自顶向下方法的匹配时间比自底向上方法慢，但预处理时间更短。

The key idea of reducing tree pattern matching to string matching is to regard each path from root to leaf in a tree as a string in which symbols in the alphabet are interleaved with numbers indicating which branch from father to son has been followed. Since variables always match, we do not include them in these strings.
将树模式匹配简化为字符串匹配的核心思想是将树中从根到叶的每条路径视为一个字符串，其中字母表中的符号与表示从父节点到子节点所遵循的分支编号交替出现。由于变量总是匹配的，因此我们不将它们包含在这些字符串中。

**Example 8.1.** The tree pattern $a(a(b, v), c)$ is associated with the set of strings ${a1a1b, a1a2, a2c}$. Note that we have omitted the symbol $v$ from the end of the second string. Figure 7 shows how the set of strings appears in the given tree.
示例 8.1。树模式 $a(a(b, v), c)$ 与字符串集 ${a1a1b, a1a2, a2c}$ 相关联。请注意，我们省略了第二个字符串末尾的符号 $v$ 。图 7 展示了该字符串集在给定树中的呈现方式。

This idea was first noticed by Karp et al. [^18] and used in a tree-matching algorithm with no preprocessing. Their algorithm achieved a matching time of
这一想法最初由 Karp 等人 [^18] 发现，并被用于一种无需预处理的树匹配算法中。他们的算法实现的匹配时间为

$$
O((\mathit{patsize} + \mathit{subsize}) \cdot \log(\mathit{patsize}))
$$

for one pattern, which must be a full binary tree. For several patterns their algorithm would require
对于单个模式，该模式必须是满二叉树。对于多个模式，他们的算法将需要

$$
O((\mathit{patsize} + \mathit{subsize}) \cdot \log(\mathit{patsize}) \cdot \mathit{patno})
$$

Our contribution is to show how, using the Knuth-Morris-Pratt algorithm for string matching, we can improve the bounds to $O(patsize)$ preprocessing, plus $O(subsize * patno)$ for matching, in the case of patterns which are full trees. If the patterns are not full trees, more time for matching is needed. We thus improve the bound of Karp et al. by a factor of $log(patsize)$.
我们的贡献在于展示了如何利用用于字符串匹配的 Knuth-Morris-Pratt 算法，在模式为满树的情况下，将边界改进为 $O(patsize)$ 预处理，外加 $O(subsize * patno)$ 匹配。如果模式不是满树，则需要更多的匹配时间。因此，我们将 Karp 等人的边界改进了 $log(patsize)$ 倍。

For simplicity of presentation we develop our results for the case of a single tree pattern first. Given the pattern $p$, it is easy to generate all path strings for the root-to-leaf paths. We could then use the algorithm of Aho and Corasick [^1] to produce an automaton which recognizes every instance of a path string within a subject tree. Since the combined length of all strings could be $O(patsize^2)$, we need to modify this construction so as to avoid generating the strings explicitly. In this way we can lower the preprocessing to $O(patsize)$.
为了便于演示，我们首先针对单个树模式的情况展开研究。给定模式 $p$ ，很容易生成所有根到叶路径的路径字符串。然后，我们可以使用 Aho 和 Corasick [^1] 的算法来生成一个自动机，该自动机可以识别主体树中路径字符串的每个实例。由于所有字符串的总长度可能是 $O(patsize^2)$ ，我们需要修改此构造，以避免显式生成字符串。通过这种方式，我们可以将预处理降低到 $O(patsize)$ 。

The first step in the Aho-Corasick algorithm is to build a trie for the path strings of the tree pattern $p$. This trie is called the "goto function" in [^1]. A trie is a tree whose nodes represent the distinct prefixes of the path strings. If node $n$ represents $x$ and $n'$ represents $xa$, $a$ in $\Sigma \cup N$, then $n$ is father of $n'$, and the edge from $n$ to $n'$ is labeled $a$. We illustrate the construction with an example. Since it amounts to a simple tree transformation, we do not formally give an algorithm.
Aho-Corasick 算法的第一步是为树模式 $p$ 的路径字符串构建一个字典树（trie）。该字典树在 [^1] 中被称为“goto 函数”。字典树是一棵树，其节点代表路径字符串的不同前缀。如果节点 $n$ 代表 $x$ ，而 $n'$ 代表 $xa$ ， $a$ 在 $\Sigma \cup N$ 中，那么 $n$ 是 $n'$ 的父节点，且从 $n$ 到 $n'$ 的边被标记为 $a$ 。我们通过一个例子来说明这种构造。由于这相当于一个简单的树变换，我们不正式给出算法。

**Figure 8.** (a) Tree pattern. (b) Associated trie.
图 8. (a) 树模式。(b) 关联的字典树（trie）。

**Example 8.2.** The pattern tree $a(a(b, v), c)$ has the associated trie shown in Figure 8. For example, the marked node represents the prefix $a2$.
例 8.2. 模式树 $a(a(b, v), c)$ 具有如图 8 所示的关联字典树。例如，标记的节点代表前缀 $a2$ 。

Informally, the trie is constructed by first enumerating the outedges of every pattern node and then splitting every node labeled with a symbol other than $v$ into two nodes connected by an edge which is labeled with the original node label.
非正式地说，字典树的构建过程是：首先枚举每个模式节点的出边，然后将每个标记有非 $v$ 符号的节点拆分为两个节点，并用一条标记有原始节点标签的边将它们连接起来。

The subsequent steps in constructing a matching automaton are exactly as in [^1], for we are now dealing with a string problem. Thus the entire construction requires $O(patsize)$ steps if we use a failure-function representation of the automaton and $O(patsize * sym)$ if we use a transition-matrix representation.
构建匹配自动机的后续步骤与 [^1] 中完全一致，因为我们现在处理的是字符串问题。因此，如果我们使用自动机的失败函数（failure-function）表示法，整个构建过程需要 $O(patsize)$ 步；如果使用转移矩阵（transition-matrix）表示法，则需要 $O(patsize * sym)$ 步。

We need to include in this construction a simple modification which records, with each accepting state of the automaton, the length(s) of the accepted string(s). The length of a path string is the number of alphabet symbols in it (numbers are ignored). Thus the length for $a2c$ and $a1a2$ is 2 in both cases.
我们需要在这一构造中加入一个简单的修改，以便在自动机的每个接受状态中记录所接受字符串的长度。路径字符串的长度是指其中包含的字母表符号的数量（忽略数字）。因此， $a2c$ 和 $a1a2$ 的长度在两种情况下均为 2。

**Figure 9.** (a) Pattern. (b) Matching automaton.
图 9. (a) 模式。(b) 匹配自动机。

**Example 8.3.** In Figure 9 we give the automaton associated with the pattern of the previous example. Accepting states are circled twice and are labeled with the length of the accepted path string.
例 8.3。在图 9 中，我们给出了与前一示例模式相关联的自动机。接受状态用双圈表示，并标有接受路径字符串的长度。

We now have to solve the problem of how the matching algorithm can decide whether two different path strings begin at the same node and thus contribute to a pattern match at that node. For this purpose we associate with each node a counter, initialized to zero. Each counter will record the number of distinct root-to-leaf paths which match beginning at that node.
现在我们必须解决匹配算法如何判断两个不同的路径字符串是否起始于同一个节点，从而在该节点处促成一次模式匹配的问题。为此，我们为每个节点关联一个初始值为零的计数器。每个计数器将记录从该节点开始匹配的、不同的“根到叶”路径的数量。

Let us traverse the subject tree $t$ in preorder, computing the automaton states as we visit nodes and traverse edges. For recovering former states when returning from a completely traversed subtree we can use the traversal stack. Every time the matching automaton enters a final state, we have matched one or more path strings, and we should indicate this fact at the points at which the matched paths begin. So we increment the counters of those nodes by 1. The traversal stack for the preorder traversal is kept in an array. Thus we can find the beginning node of a matched path string in the traversal stack and can access it in constant time once we know the length of the matched string.
让我们以先序遍历的方式遍历主体树 $t$ ，在访问节点和遍历边时计算自动机状态。当从一个已完全遍历的子树返回时，我们可以使用遍历栈来恢复之前的状态。每当匹配自动机进入终止状态时，意味着我们已经匹配了一个或多个路径字符串，我们应当在这些匹配路径的起始点标记这一事实。因此，我们将这些节点的计数器加 1。先序遍历的遍历栈保存在一个数组中。这样，一旦我们知道了匹配字符串的长度，就可以在遍历栈中找到该匹配路径字符串的起始节点，并能在常数时间内访问它。

At the end of the traversal the pattern matches at each node whose counter equals the number of leaves in the pattern (i.e., the number of path strings). We can now give the matching algorithm.
在遍历结束时，如果某个节点的计数器等于模式中的叶子节点数量（即路径字符串的数量），则该节点处存在模式匹配。现在我们可以给出匹配算法。

We will use an array of triples $(n, s, j)$ as traversal stack, where $n$ is a node in the subject tree, $s$ the state the automaton has entered when the traversal visits $n$, and $j$ a number indicating how many sons of $n$ have been visited. Additionally, we have an array `Count`, indexed by nodes $n$ of the subject tree, which contains the associated counters.
我们将使用一个三元组数组 $(n, s, j)$ 作为遍历栈，其中 $n$ 是主体树中的一个节点， $s$ 是遍历访问 $n$ 时自动机进入的状态，而 $j$ 是一个表示已访问过 $n$ 的多少个子节点的数字。此外，我们还有一个由主体树节点 $n$ 索引的数组 `Count` ，其中包含相关的计数器。

We assume that the algorithm uses a transition-table representation of the automaton and indicate by $A[s, c]$ the state the automaton enters when in state $s$ reading symbol $c$.
我们假设该算法使用自动机的转换表表示，并用 $A[s, c]$ 表示自动机在状态 $s$ 下读取符号 $c$ 时进入的状态。

We use a procedure `Tabulate`, which maintains the counters and updates the list of matches found. This procedure can access the stack of triples.
我们使用过程 `Tabulate` ，该过程负责维护计数器并更新已发现的匹配列表。此过程可以访问三元组栈。

**Algorithm D (Top-Down Matching)
算法 D (自顶向下匹配)**

Input: A string matching automaton for tree pattern $p$ in transition matrix representation, and a subject tree $t$.
输入：树模式 $p$ 的转移矩阵表示形式的字符串匹配自动子，以及目标树 $t$ 。
Output: A list, `Match`, of all nodes in $t$ at which $p$ matches.
输出：列表 `Match` ，包含 $t$ 中所有与 $p$ 匹配的节点。
Comment: $A[s, c]$ is the state entered from $s$ under input $c$ in the matching automaton. $Stack[i].j$ denotes the $j$th component of the triple stacked at position $i$ in the array `Stack`. $\operatorname{son}_i(n)$ denotes the $i$th son of tree node $n$.
注释： $A[s, c]$ 是匹配自动机中在输入 $s$ 下从状态 $c$ 进入的状态。 $Stack[i].j$ 表示数组 `Stack` 中位置 $i$ 处堆叠的三元组的第 $j$ 个分量。 $\operatorname{son}_i(n)$ 表示树节点 $n$ 的第 $i$ 个子节点。

```
1.  Match := empty.
2.  For all nodes n in t do Count[n] := 0.
3.  Nextstate := A[start state, label(root of t)].
4.  Top := 1.
5.  Stack[Top] := (root of t, Nextstate, 0).
6.  Tabulate(Nextstate).
7.  While Top > 0 do:
8.    (Thisnode, Thisstate, Nsons) := Stack[Top].
9.    If Nsons = arity(Thisnode) then Top := Top - 1.
10.   Else:
11.     Nsons := Nsons + 1.
12.     Stack[Top].3 := Nsons.
13.     Intstate := A[Thisstate, Nsons].
14.     Tabulate(Intstate).
15.     Nextnode := son_{Nsons}(Thisnode).
16.     Nextstate := A[Intstate, label(Nextnode)].
17.     Top := Top + 1.
18.     Stack[Top] := (Nextnode, Nextstate, 0).
19.     Tabulate(Nextstate).
20.   End if.
21. End while.

Procedure Tabulate(State)
1.  For all s such that State has a match of length s do:
2.    n := Stack[Top - s + 1].1.
3.    Count[n] := Count[n] + 1.
4.    If Count[n] = number of leaves in pattern then:
5.      Add n to Match.
6.  End for.
```

Except for the work of procedure `Tabulate`, the complexity of Algorithm D is $O(subsize)$, since each edge is traversed at most twice. This is also true for the failure-function representation of the matching automaton (see [^1]). The total work of procedure `Tabulate` is proportional to the number of times any counter has been incremented, or equivalently, to the sum of all counter values upon completion of the traversal. We can estimate this sum by deriving a bound on the number of different counters which can be incremented in an accepting state, for this will also bound the work done for each call of the procedure.
除了过程 `Tabulate` 的工作外，算法 D 的复杂度为 $O(subsize)$ ，因为每条边最多被遍历两次。对于匹配自动机的失效函数表示法（见 [^1]）也是如此。过程 `Tabulate` 的总工作量与任何计数器递增的次数成正比，或者等价于遍历完成时所有计数器值的总和。我们可以通过推导在接受状态下可能递增的不同计数器数量的界限来估算这个总和，因为这也将限制每次调用该过程所做的工作。

**Definition 8.1.** Given a tree pattern $p$ and a path string $s$ of $p$, the suffix number of $s$ is the number of path strings of $p$ which are suffixes of $s$, including $s$ itself. The suffix index of $p$ is the maximum suffix number of the path strings of $p$.
定义 8.1。给定一个树模式 $p$ 和 $p$ 的路径字符串 $s$ ， $s$ 的后缀数是作为 $s$ 后缀的 $p$ 的路径字符串的数量，包括 $s$ 本身。 $p$ 的后缀索引是 $p$ 的路径字符串的最大后缀数。

Equivalently, the suffix index is the largest number of counters which could be incremented in any accept state of the automaton.
等价地，后缀索引是自动机在任何接受状态下可能递增的计数器的最大数量。

**Example 8.4.** For the pattern $p = a(a(a(v, b), c), b)$ we have the path strings $a1a1a1$, $a1a1a2b$, $a1a2c$, $a2b$. The suffix number of $a1a1a1$ is 1, whereas the suffix number of $a1a1a2b$ is 2, since $a2b$ is a suffix which occurs as root-to-leaf path in $p$. The suffix index of $p$ is also 2.
例 8.4。对于模式 $p = a(a(a(v, b), c), b)$ ，我们有路径字符串 $a1a1a1$ 、 $a1a1a2b$ 、 $a1a2c$ 、 $a2b$ 。 $a1a1a1$ 的后缀编号为 1，而 $a1a1a2b$ 的后缀编号为 2，因为 $a2b$ 是在 $p$ 中作为根到叶路径出现的后缀。 $p$ 的后缀索引也为 2。

**Theorem 8.1.** Algorithm D requires $O(subsize * suf)$ steps, where $suf$ is the suffix index of the pattern to be matched.
定理 8.1。算法 D 需要 $O(subsize * suf)$ 个步骤，其中 $suf$ 是待匹配模式的后缀索引。

For patterns which are full trees, that is, all path strings are of equal length, $suf$ must be 1, since a distinct path string $s_1$ can be a proper suffix of a distinct path string $s_2$ only if $s_1$ is shorter than $s_2$. This gives us:
对于全树模式（即所有路径字符串长度相等）， $suf$ 必须为 1，因为只有当 $s_1$ 比 $s_2$ 短时，不同的路径字符串 $s_1$ 才能是另一个不同路径字符串 $s_2$ 的真后缀。由此我们得到：

**Corollary 8.2.** If Algorithm D matches a pattern which is a full tree, then only $O(subsize)$ steps are needed.
推论 8.2。如果算法 D 匹配一个全树模式，则只需要 $O(subsize)$ 个步骤。

In the worst case, $suf$ could be $O(patsize)$.
在最坏情况下， $suf$ 可能是 $O(patsize)$ 。

**Example 8.5.** Consider the pattern
示例 8.5。考虑模式

$$
p_k = a(\underbrace{a(\ldots a(v, b) \ldots b)}_{k \text{ times}}, b)
$$

Its suffix index is $k$, owing to the path string $(a1)^{k-1}a2b$, which has every shorter path string as suffix. Note that $patsize$ is $2k + 1$.
其后缀索引为 $k$ ，这是由于路径字符串 $(a1)^{k-1}a2b$ 造成的，该字符串将每个较短的路径字符串都作为后缀。注意 $patsize$ 是 $2k + 1$ 。

**Corollary 8.3.** The bound of $O(subsize * patsize)$ for Algorithm D is attained for certain patterns.
推论 8.3。算法 D 的 $O(subsize * patsize)$ 界限在某些模式下可以达到。

**Proof.** Consider matching the pattern $p_k$ of Example 8.5 in the subject
证明。考虑匹配主题中示例 8.5 的模式 $p_k$

$$
t_n = a(\underbrace{a(\ldots a(c, b) \ldots b)}_{n \text{ times}}, b)
$$

where $n = k + m$. Then the sum of the counter values in $t_n$ after Algorithm D has finished exceeds $m * k$. Note that $patsize$ is $2k + 1$ and $subsize$ is $2n + 1$.
其中 $n = k + m$ 。那么在算法 D 运行结束后， $t_n$ 中的计数器值之和超过了 $m * k$ 。注意 $patsize$ 是 $2k + 1$ ，且 $subsize$ 是 $2n + 1$ 。

We thus have in Algorithm D a performance range anywhere between that of the bottom-up algorithm and that of the naive matching algorithm, depending on the structure of the pattern.
因此，在算法 D 中，其性能范围介于自底向上算法和朴素匹配算法之间，具体取决于模式的结构。

Without going into details we note that Algorithm D may be adapted to assimilate local changes in the subject tree. As in the case of the bottom-up algorithm, we need to reprocess only a small area surrounding the part which has changed. However, the algorithmic details are far more complicated than in the case of the bottom-up algorithm, although in principle quite straightforward.
在不深入细节的情况下，我们注意到算法 D 可以经过调整以吸收主题树中的局部变化。与自底向上算法的情况一样，我们只需要重新处理发生变化的部分周围的一小块区域。然而，尽管原则上非常简单，但其算法细节要比自底向上算法的情况复杂得多。

We conclude this section with a brief discussion of how to match more than one tree pattern, using the approach of Algorithm D.
在本节的最后，我们将简要讨论如何使用算法 D 的方法来匹配多个树模式。

Recall that we represent a tree pattern by its root-to-leaf path strings. We can do this for several patterns as well, but we should keep track of which pattern(s) each path string comes from. The preprocessing algorithm can be adapted to process several patterns by building separately for each pattern the associated trie and then merging these tries, keeping track of which pattern(s) each path string at a leaf of the trie belongs to. This can be done in $O(patsize)$ steps resulting in a trie of $O(patsize)$ nodes. Now apply the methods of [^1] to complete the trie to a matching automaton.
回想一下，我们通过根到叶子的路径字符串来表示树模式。我们也可以对多个模式执行此操作，但我们应该记录每个路径字符串来自哪个（或哪些）模式。预处理算法可以通过以下方式适应处理多个模式：分别为每个模式构建关联的字典树（trie），然后合并这些字典树，并记录字典树叶子节点处的每个路径字符串属于哪个（或哪些）模式。这可以在 $O(patsize)$ 步内完成，生成一个具有 $O(patsize)$ 个节点的字典树。现在应用 [^1] 中的方法将该字典树完善为一个匹配自动机。

In the case of a single pattern we associated with each of the final states a list of the lengths of the matched path strings. For multiple patterns we now associate with final states lists of pairs. Each pair gives the length of the matched path string and the pattern to which it belongs.
在单个模式的情况下，我们将每个最终状态与匹配路径字符串的长度列表相关联。对于多个模式，我们现在将最终状态与“对（pair）”列表相关联。每个对分别给出匹配路径字符串的长度及其所属的模式。

It remains to explain how we can correlate matches of individual path strings. We do this simply by associating $patno$ counters with each node in the subject tree and dedicating the $i$th counter to counting how many path strings of the $i$th pattern have been matched, beginning at that node. If the $i$th counter reaches a value equal to the number of leaves of the $i$th pattern, then we have just matched the $i$th pattern.
剩下的工作是解释我们如何关联单个路径字符串的匹配。我们只需通过为主题树中的每个节点关联 $patno$ 个计数器来实现这一点，并专门使用第 $i$ 个计数器来统计从该节点开始，第 $i$ 个模式有多少个路径字符串已匹配。如果第 $i$ 个计数器的值达到了第 $i$ 个模式的叶子节点数量，那么我们就刚刚匹配了第 $i$ 个模式。

As before, the work is proportional to the subject size plus the sum of all counter values and can be estimated as
和之前一样，工作量与主体大小加上所有计数器值的总和成正比，可以估计为

$$
O(\mathit{subsize} \cdot \max(\mathit{suf}) \cdot \mathit{patno})
$$

where the maximum is taken over all tree patterns in the forest. This bound is easily shown to be the best possible, generalizing Corollary 8.2. Furthermore, if no path string is a suffix of another, then we have only $O(subsize)$ steps for matching such a pattern forest.
其中最大值取自森林中所有的树模式。这一界限很容易被证明是目前所能达到的最佳界限，它推广了推论 8.2。此外，如果没有路径字符串是另一个路径字符串的后缀，那么匹配这样一个模式森林只需要 $O(subsize)$ 步。

## 9\. Improvements to Top-Down Matching and Related Work
9\. 对自顶向下匹配的改进及相关工作

Recently, Lang et al. [^24] improved Algorithm D by basing the matching of path strings on the Boyer-Moore algorithm [^4]. Since the Boyer-Moore algorithm requires the ability to skip portions of the subject string, a different representation of trees is used: Trees are represented by ordered lists of left paths.
最近，Lang 等人 [^24] 通过将路径字符串的匹配基于 Boyer-Moore 算法 [^4] 改进了算法 D。由于 Boyer-Moore 算法需要能够跳过主体字符串的部分内容，因此使用了不同的树表示方法：树由左路径的有序列表表示。

**Figure 10.** Left-path representation of the tree $a(b(c), a(d, c))$.
图 10. 树 $a(b(c), a(d, c))$ 的左路径表示。

**Example 9.1.** For the tree $t = a(b(c), a(d, c))$ the list of left paths is $<abc, ad, c>$, as shown in Figure 10.
例 9.1. 对于树 $t = a(b(c), a(d, c))$ ，其左路径列表为 $<abc, ad, c>$ ，如图 10 所示。

We can obtain left paths by first deleting from each path string the longest prefix ending with a branch number greater than 1 and then deleting the remaining branch numbers. Thus, from $a2a1d$ we obtain $ad$, and from $a2a2c$ we get $c$. The list of these left paths uniquely determines a binary tree. For alphabet symbols of arity higher than 2, additional information has to be given for each left path string.
我们可以通过以下方式获取左路径：首先从每个路径字符串中删除以大于 1 的分支编号结尾的最长前缀，然后删除剩余的分支编号。因此，从 $a2a1d$ 我们得到 $ad$ ，从 $a2a2c$ 我们得到 $c$ 。这些左路径的列表唯一地确定了一棵二叉树。对于元数大于 2 的字母表符号，必须为每个左路径字符串提供额外的信息。

The algorithm first preprocesses the list of left paths of the pattern, constructing a Boyer-Moore-type automaton for recognizing the first left path, combined with an Aho-Corasick-type automaton for recognizing the remaining left paths. A match of the remaining left paths is attempted only at places at which the first left path has been completely matched. Note that the advantages of the Boyer-Moore machine diminish as the number of different strings to be matched increases. See [^8] for a discussion of this phenomenon. The subject tree is also represented as an ordered list of (linked) left paths, so that we can skip ahead for the Boyer-Moore matching technique.
该算法首先对模式的左路径列表进行预处理，构建一个用于识别第一条左路径的 Boyer-Moore 型自动机，并结合一个用于识别其余左路径的 Aho-Corasick 型自动机。仅在第一条左路径完全匹配的位置，才会尝试匹配其余的左路径。请注意，随着待匹配字符串数量的增加，Boyer-Moore 机的优势会减弱。有关此现象的讨论请参见 [^8]。主题树也表示为（链接的）左路径有序列表，以便我们可以利用 Boyer-Moore 匹配技术进行跳跃。

A subtlety of the algorithm, when it is applied to trees of arity exceeding 2, arises from the fact that a match of the $j$th left path implies an update of the appropriate counter only if the counter has a specific value, because the left path may be descending from a node with more than two sons. For details see [^24].
当该算法应用于度数超过 2 的树时，会出现一个微妙之处：仅当计数器具有特定值时，匹配第 $j$ 条左路径才意味着更新相应的计数器，因为左路径可能是从具有两个以上子节点的节点下降的。详情请参见 [^24]。

Lang et al. [^24] implemented both their algorithm and our Algorithm D. First experiments seem to indicate a sublinear average matching time for their algorithm. The worst-case performance of their algorithm is the same as that of Algorithm D.
Lang 等人 [^24] 实现了他们的算法和我们的算法 D。初步实验似乎表明他们的算法具有亚线性的平均匹配时间。他们算法的最坏情况性能与算法 D 相同。

Overmars and van Leeuwen [^27] have given algorithms to match lexicographic trees, that is, trees in which the branches rather than the nodes are labeled with symbols from an alphabet. They assume that the branches emanating from each node are ordered left to right by their labels and that no label occurs more than once. Lexicographic trees arise as tries.
Overmars 和 van Leeuwen [^27] 给出了匹配字典树（lexicographic trees）的算法，即树的分支而非节点被标记为字母表中的符号。他们假设从每个节点发出的分支按其标签从左到右排序，并且没有标签出现超过一次。字典树以字典树（tries）的形式出现。

Overmars and van Leeuwen consider matching a given lexicographic tree (the pattern) in a larger lexicographic tree (the subject). A match is an alignment of the pattern nodes with certain subject nodes. The alignment must respect the father-son relation in such a way that the branches emanating from a subject node are labeled with the same symbol as the corresponding pattern branches. Note that not all branches of a subject node need to be covered by corresponding pattern branches.
Overmars 和 van Leeuwen 考虑在较大的字典树（主体）中匹配给定的字典树（模式）。匹配是模式节点与某些主体节点的对齐。这种对齐必须遵循父子关系，使得从主体节点发出的分支与相应的模式分支标记有相同的符号。请注意，主体节点的所有分支并不一定都需要被相应的模式分支覆盖。

Their algorithms were discovered independently from our work. Their technique, like our Algorithm D, is based on Karp et al.'s idea of matching path strings. In the case of lexicographic trees, however, no branch numbers need to be interleaved in path strings. Overmars and van Leeuwen also use counters to coordinate the matches of path strings.
他们的算法是独立于我们的工作发现的。他们的技术与我们的算法 D 类似，也是基于 Karp 等人匹配路径字符串的思想。然而，在字典树的情况下，路径字符串中不需要交错插入分支编号。Overmars 和 van Leeuwen 同样使用计数器来协调路径字符串的匹配。

Their best algorithm does preprocessing of the pattern similar to ours, identifying for each path string the suffixes which are also path strings. They give the preprocessing in their own terminology, but it amounts essentially to the algorithms of [^1]. Their best matching algorithm has the same worst-case time bound as our Algorithm D. Other algorithms given in [^27] do little or no preprocessing of the pattern and have inferior bounds on the matching time.
他们最优的算法对模式进行了类似于我们的预处理，即识别每个路径字符串中同时也是路径字符串的后缀。他们用自己的术语给出了预处理过程，但实质上等同于 [^1] 中的算法。他们最优的匹配算法与我们的算法 D 具有相同的最坏情况时间界限。[^27] 中给出的其他算法对模式进行的预处理很少或根本没有，且匹配时间的界限较差。

We wish to stress that the approaches of Algorithm D, Overmars and van Leeuwen, and Lang et al. are inherently limited by using counters for deciding whether there is a match. As long as counters are used and incremented in steps of one up to the number of leaves of a pattern, a simple counting argument shows that the bound of Theorem 8.1 cannot be improved except by a constant factor. We see only two ways for improving this situation. Either means are found to increment counters in larger steps (or, equivalently, to smaller values) or a new method for coordinating path strings is used. The former would imply that recording of matches is delayed in some way. For the latter approach we can offer a solution which reduces the worst-case bound to $O(subsize + match)$.
我们想强调的是，算法 D、Overmars 和 van Leeuwen 以及 Lang 等人的方法本质上都受到使用计数器来判定是否匹配的限制。只要使用计数器并以 1 为步长递增直至模式的叶节点数量，一个简单的计数论证就表明，定理 8.1 的界限除了常数因子外无法再改进。我们认为只有两种方法可以改善这种情况：要么找到以更大步长递增计数器（或等效地递增至更小的值）的方法，要么使用一种新的协调路径字符串的方法。前者意味着匹配的记录会以某种方式延迟。对于后者，我们可以提供一种将最坏情况界限降低到 $O(subsize + match)$ 的解决方案。

Assuming a machine model in which, in constant time, we can perform bit-string operations of union, intersection, and right shift by one position, we can improve Algorithm D as follows. We associate with each node $n$ of the subject tree a bit string $b_n$ in which the $i$th bit (from the right) is 1 iff every path from the ancestor of $n$ at distance $i$, through $n$, to every descendant of $n$, has a prefix which is a path string of the pattern we wish to match. Note that we do not need to use bit strings longer than the height of the pattern. There is a match of the pattern at node $n$ iff $b_n$ has a 1 in the rightmost position.
假设在一种机器模型中，我们可以在常数时间内执行位串的并集、交集和右移一位操作，那么我们可以按如下方式改进算法 D。我们为主题树的每个节点 $n$ 关联一个位串 $b_n$ ，其中（从右侧起）第 $i$ 位为 1，当且仅当从 $n$ 的距离为 $i$ 的祖先开始，经过 $n$ ，到 $n$ 的每个后代的所有路径，都具有一个作为我们要匹配的模式路径字符串的前缀。注意，我们不需要使用比模式高度更长的位串。当且仅当 $b_n$ 的最右侧位置为 1 时，节点 $n$ 处存在模式匹配。

**Figure 11.** (a) Pattern. (b) Subject.
图 11。(a) 模式。(b) 主题。

**Example 9.2.** Consider the tree pattern $a(a(b(v), c), a(v, v))$. Assume we wish to match it in the subject fragment shown in Figure 11. We should assign the bit string $100$ to node 3, since we have a match of the path string $a1a1b1$, and also to node 4, because of the path string $a1a2c$. Note that both path strings are of length 3. To node 5 the bit string $010$ is assigned, because the two path strings $a2a1$ and $a2a2$ match, both of length 2. To node 2 we assign the bit string $010$, since every path originating at node 1, the ancestor of node 2 at distance 1, and going through node 2 has a prefix which is a path string in the pattern. Note that $010$ can be obtained as the right shift by one of $(100 \cap 100)$, the intersection of the two bitstrings assigned to the two sons of node 2. Node 1 will be assigned the bitstring $001$. The 1 at the extreme right signals the presence of a pattern match.
例 9.2。考虑树模式 $a(a(b(v), c), a(v, v))$ 。假设我们希望在图 11 所示的主题片段中对其进行匹配。我们应该给节点 3 分配位串 $100$ ，因为我们匹配了路径字符串 $a1a1b1$ ；同样给节点 4 分配该位串，因为匹配了路径字符串 $a1a2c$ 。注意这两个路径字符串的长度均为 3。给节点 5 分配位串 $010$ ，因为两个路径字符串 $a2a1$ 和 $a2a2$ 均匹配，且长度均为 2。给节点 2 分配位串 $010$ ，因为每一个源自节点 1（节点 2 距离为 1 的祖先）并经过节点 2 的路径，都具有一个作为模式中路径字符串的前缀。注意 $010$ 可以通过将节点 2 的两个子节点所分配位串的交集 $(100 \cap 100)$ 右移一位来获得。节点 1 将被分配位串 $001$ 。最右侧的 1 标志着存在一个模式匹配。

Note that in this example bit strings of length 3 are used, since the length of the longest path string in the pattern is 3. We need to explain how these bit strings can be computed. During preprocessing we associate with each accepting state $s$ a bit string $b_s$, in which the $i$th bit is 1 iff a path string of length $i$ is accepted. By carefully considering the techniques of [^1] we can design this preprocessing step to require $O(patsize)$ time at most.
注意在这个例子中使用了长度为 3 的位串，因为模式中最长路径字符串的长度为 3。我们需要解释如何计算这些位串。在预处理期间，我们将每个接受状态 $s$ 与一个位串 $b_s$ 相关联，其中第 $i$ 位为 1 当且仅当长度为 $i$ 的路径字符串被接受。通过仔细考虑 [^1] 中的技术，我们可以将此预处理步骤设计为最多需要 $O(patsize)$ 时间。

Traverse the subject tree in preorder as before. When reaching a node for the first time in the traversal, initialize $b_n$ to $b_s$, where $s$ is the corresponding state in the matching automaton. Then, when coming to $n$ for the last time, that is, after all subtrees have been visited, update $b_n$ by
像以前一样按先序遍历主题树。在遍历中第一次到达某个节点时，将 $b_n$ 初始化为 $b_s$ ，其中 $s$ 是匹配自动机中的相应状态。然后，在最后一次回到 $n$ 时，即在访问完所有子树之后，通过以下方式更新 $b_n$ ：

$$
b_n := b_n \cup \bigcap_j \operatorname{rightshift}(b_{\operatorname{son}_j(n)})
$$

where $rightshift$ means a shift by one bit position to the right, introducing 0 on the left. This method then has, as worst case, $O(subsize + match)$ time requirement for matching, since we eliminated the work of procedure `Tabulate`.
其中 $rightshift$ 表示向右移动一个比特位，并在左侧补 0。由于我们消除了过程 `Tabulate` 的工作，该方法在最坏情况下的匹配时间需求为 $O(subsize + match)$ 。

Note that we need not associate bit strings with nodes permanently: Upon completing the traversal of a subtree rooted in $n$, the bit strings associated with the sons of $n$ are no longer needed. Thus we may keep all bit strings in the traversal stack (plus $rank$ additional cells). Similarly, we could have reduced the space requirements for Algorithm D by keeping the counters on the traversal stack.
请注意，我们不必永久地将位串与节点关联：在完成以 $n$ 为根的子树遍历后，与 $n$ 的子节点关联的位串就不再需要了。因此，我们可以将所有位串保存在遍历栈中（外加 $rank$ 个额外单元）。同样地，我们也可以通过将计数器保存在遍历栈中，来减少算法 D 的空间需求。

## 10\. Bottom-Up Matching with Bit-String Operations
10\. 基于位串操作的自底向上匹配

Since most computers allow unions, intersections, and complements of sets represented as bit strings to be performed in a small fixed number of instructions, we explore the possibility of representing match sets by bit strings and computing them directly at match time, thus avoiding the costly table generation of Section 6.
由于大多数计算机允许以较小的固定指令数对表示为位串的集合执行并集、交集和补集运算，我们探索了用位串表示匹配集并在匹配时直接计算它们的可能性，从而避免了第 6 节中昂贵的表生成过程。

Let $F$ be a pattern forest and $PF$ the set of all subpatterns in $F$.
设 $F$ 为模式森林， $PF$ 为 $F$ 中所有子模式的集合。

**Definition 10.1.** Define the sets $U_a$ for each $a$ in the alphabet as follows:
定义 10.1。为字母表中的每个 $a$ 定义集合 $U_a$ 如下：

$$
U_a = \begin{cases} \{v\} & \text{if } a \text{ is nullary and not in } PF,\\ \{a, v\} & \text{if } a \text{ is nullary and in } PF,\\ \{t \in PF \mid t = a(t_1, \ldots, t_q)\} \cup \{v\} & \text{if } a \text{ is } q\text{-ary}, q > 0. \end{cases}
$$

Furthermore, define a set-valued function on pattern sets by
此外，在模式集上定义一个集值函数如下：

$$
\operatorname{Father}_i(M) = \{t' \in PF \mid \operatorname{son}_i(t') \in M\}.
$$

We now recast Definition 4.2 as follows.
我们现在将定义 4.2 重述如下。

**Definition 10.2
定义 10.2**

1.  $\operatorname{Match}(a) = U_a$ if $a$ is nullary.
    如果 $a$ 是零元的，则为 $\operatorname{Match}(a) = U_a$ 。
2.  $\operatorname{Match}(a(t_1, \ldots, t_q))$ is
    $\operatorname{Match}(a(t_1, \ldots, t_q))$ 是

$$
(U_a \cap \operatorname{Father}_1(\operatorname{Match}(t_1)) \cap \cdots \cap \operatorname{Father}_q(\operatorname{Match}(t_q))) \cup \{v\}.
$$

Part (2) says that the subpatterns which match at $a(t_1, \ldots, t_q)$ are exactly $v$ plus those trees within $U_a$ whose sons match the $t_1, \ldots, t_q$. A table for the sets $U_a$ is easily precomputed in a single pass over the patterns in $F$ in $O(patsize)$ time and $O(sym)$ additional space. Now, if we can find a simple way to compute $\operatorname{Father}_i(M)$, we may assign match sets in bit-string form to each node of the subject in a simple postorder traversal of the subject tree.
第 (2) 部分指出，在 $a(t_1, \ldots, t_q)$ 处匹配的子模式恰好是 $v$ 加上 $U_a$ 中那些其子节点匹配 $t_1, \ldots, t_q$ 的树。 $U_a$ 集合表可以很容易地在 $O(patsize)$ 时间和 $O(sym)$ 额外空间内，通过对 $F$ 中的模式进行单次扫描预计算得出。现在，如果我们能找到一种简单的方法来计算 $\operatorname{Father}_i(M)$ ，我们就可以在对目标树进行简单的后序遍历时，为目标的每个节点分配位串形式的匹配集合。

A direct computation of $\operatorname{Father}_i(M)$ seems to require a loop through all subpatterns. We suggest therefore a hashing approach. We precompute a hash table for all match sets and store $\operatorname{Father}_i(M)$ for $1 \le i \le rank$ at the table entry for $M$. Such a table consumes $O((set/load) * rank)$, where $load$ is the loading factor of the hash table, compared to $O(set^rank * sym)$ for the tables described in Section 4.
直接计算 $\operatorname{Father}_i(M)$ 似乎需要遍历所有子模式。因此，我们建议使用哈希方法。我们为所有匹配集合预计算一个哈希表，并在 $M$ 的表项中存储 $1 \le i \le rank$ 的 $\operatorname{Father}_i(M)$ 。与第 4 节中描述的表所需的 $O(set^rank * sym)$ 相比，此类表消耗 $O((set/load) * rank)$ ，其中 $load$ 是哈希表的负载因子。

Given a hashing function for the $M$, the precomputation of $\operatorname{Father}_i(M)$ in the most straightforward way takes time
给定 $M$ 的哈希函数，以最直接的方式预计算 $\operatorname{Father}_i(M)$ 所需的时间为

$$
O(\mathit{set} \cdot \mathit{rank} \cdot \mathit{patsize})
$$

In time $O(set * patno)$ we can add to each entry $M$ a list of indices $i$ such that the entire pattern $p_i$ is in $M$. This list allows us to detect matches immediately from the match sets. The only additional problem is how to choose a suitable hashing function. Since we deal with a fixed forest of tree patterns, we would like to derive "perfect" hashing functions [^32], that is, hashing functions which have no collisions on the set of keys. For this, we offer two alternatives.
在时间 $O(set * patno)$ 内，我们可以为每个条目 $M$ 添加一个索引列表 $i$ ，使得整个模式 $p_i$ 都在 $M$ 中。该列表允许我们直接从匹配集中检测匹配项。唯一额外的问题是如何选择合适的哈希函数。由于我们处理的是固定的树模式森林，我们希望推导出“完美”哈希函数 [^32]，即在键集上没有冲突的哈希函数。为此，我们提供两种替代方案。

In the case of simple pattern forests, we take advantage of the results of Section 5, which showed that all match sets have singleton base sets. We enumerate the patterns in $PF$ in increasing order of subsumption, for example, a depth-first numbering of $G_S$. In this way the base-set subpattern is always represented by the leftmost nonzero bit in the string representation of the set. Since different match sets have different base sets, they must have different numbers of leading zeros. Our hashing function now simply counts the leading bits, thereby achieving a perfect minimal hashing function. Note that a practical implementation of this is possible, since on most computers there is an instruction to normalize floating-point numbers, which involves counting leading zero bits.
在简单模式森林的情况下，我们利用第 5 节的结果，该结果表明所有匹配集都具有单元素基集。我们按照包含关系的递增顺序枚举 $PF$ 中的模式，例如对 $G_S$ 进行深度优先编号。通过这种方式，基集子模式始终由集合字符串表示中最左侧的非零位表示。由于不同的匹配集具有不同的基集，它们必须具有不同数量的前导零。现在的哈希函数只需计算前导位，从而实现一个完美的最小哈希函数。请注意，这在实际中是可行的，因为大多数计算机都有规范化浮点数的指令，其中就涉及计算前导零位。

For nonsimple forests the work of Sprugnoli can be used [^32]. His algorithms derive a perfect hashing function using multiplication, addition, and division, but the function does not guarantee a high loading factor. Unfortunately, there is no analysis of his algorithms, so the exact space and time bounds are not known. Further research is needed to investigate whether there are special properties of match sets which lead to minimal perfect hashing functions which can be derived in a reasonable amount of time.
对于非简单森林，可以使用 Sprugnoli 的研究成果 [^32]。他的算法利用乘法、加法和除法推导出完美哈希函数，但该函数不能保证高负载因子。遗憾的是，目前尚无对其算法的分析，因此确切的空间和时间边界尚不清楚。需要进一步研究以探讨匹配集是否存在某些特殊属性，从而能够推导出可以在合理时间内计算出的最小完美哈希函数。

Bit-string representation of match sets offers another advantage. Recall that the number of match sets may be exponential in the pattern size. Therefore we should control the table size in those cases. This is possible with the following observation about the $Father$ function:
匹配集的位串表示还提供了另一个优势。回想一下，匹配集的数量可能随模式大小呈指数级增长。因此，在这些情况下，我们应该控制表的大小。通过对 $Father$ 函数的以下观察，这是可以实现的：

$$
\operatorname{Father}_i(M_1 \cup M_2) = \operatorname{Father}_i(M_1) \cup \operatorname{Father}_i(M_2).
$$

**Table II. Space and time complexities for preprocessing and matching techniques.
表 II. 预处理和匹配技术的空间与时间复杂度。**

| Method方法 | Restrictions限制 | Preprocessing time预处理时间 | Matching time匹配时间 | Preprocessing space预处理空间 | Matching space excluding space occupied by output匹配空间（不包括输出占用的空间） |
| --- | --- | --- | --- | --- | --- |
| Naive algorithm朴素算法 | None无 | None无 | O(subsize∗patsize)O(subsize \* patsize)O(subsize∗patsize) | None无 | O(subsize+patsize)O(subsize + patsize)O(subsize+patsize) |
| Bottom up with preprocessing带预处理的自底向上 | None无 | O(set(rank+1)∗sym∗patsize)O(set^(rank+1) \* sym \* patsize)O(set(rank+1)∗sym∗patsize) | O(subsize+match)O(subsize + match)O(subsize+match) | O(setrank∗sym)O(set^rank \* sym)O(setrank∗sym) | O(subsize+setrank∗sym)O(subsize + set^rank \* sym)O(subsize+setrank∗sym) |
| Bottom up with Algorithms A and B结合算法 A 和 B 的自底向上 | Simple pattern forest简单模式森林 | O(patsize2∗rank+ht∗sym∗patsizerank)O(patsize^2 \* rank + ht \* sym \* patsize^rank)O(patsize2∗rank+ht∗sym∗patsizerank) | O(subsize+match)O(subsize + match)O(subsize+match) | O(patsize2+patsizerank∗sym)O(patsize^2 + patsize^rank \* sym)O(patsize2+patsizerank∗sym) | O(subsize+patsizerank∗sym)O(subsize + patsize^rank \* sym)O(subsize+patsizerank∗sym) |
| Bottom up with Algorithm C使用算法 C 自下而上 | Simple binary forest简单二叉森林 | O(patsize∗ht2)O(patsize \* ht^2)O(patsize∗ht2) | O(subsize∗ht2+match)O(subsize \* ht^2 + match)O(subsize∗ht2+match) | O(patsize2)O(patsize^2)O(patsize2) | O(subsize+patsize2)O(subsize + patsize^2)O(subsize+patsize2) |
| Top down with Algorithm D使用算法 D 的自顶向下方法 | Patterns are full trees模式为全树 | O(patsize)O(patsize)O(patsize) | O(subsize∗patno)O(subsize \* patno)O(subsize∗patno) | O(patsize)O(patsize)O(patsize) | O(subsize∗patno+patsize)O(subsize \* patno + patsize)O(subsize∗patno+patsize) |
| Top down with Algorithm D使用算法 D 的自顶向下方法 | None无 | O(patsize)O(patsize)O(patsize) | O(subsize∗suf)O(subsize \* suf)O(subsize∗suf) | O(patsize)O(patsize)O(patsize) | O(subsize∗patno+patsize)O(subsize \* patno + patsize)O(subsize∗patno+patsize) |
| Top down with bit-string operations使用位串操作的自顶向下方法 | Uniform cost for bit-string operations位串操作的均匀代价 | O(patsize)O(patsize)O(patsize) | O(subsize+match)O(subsize + match)O(subsize+match) average; O(subsize∗set)O(subsize \* set)O(subsize∗set) worst case O(subsize+match)O(subsize + match)O(subsize+match) 平均； O(subsize∗set)O(subsize \* set)O(subsize∗set) 最坏情况 | O(set/load)O(set/load)O(set/load) | O(subsize+(set/load)∗(rank+patno)+sym)O(subsize + (set/load) \* (rank + patno) + sym)O(subsize+(set/load)∗(rank+patno)+sym) |
| Bottom up with perfect hashing使用完美哈希的自底向上法 | Uniform cost for bit-string operations; simple forest位串操作的统一代价；简单森林 | O(set∗rank∗patsize+patno)O(set \* rank \* patsize + patno)O(set∗rank∗patsize+patno) | O(subsize+match)O(subsize + match)O(subsize+match) | O(set∗(rank+patno))O(set \* (rank + patno))O(set∗(rank+patno)) | O(subsize+(set/load)∗(rank+patno)+sym)O(subsize + (set/load) \* (rank + patno) + sym)O(subsize+(set/load)∗(rank+patno)+sym) |
| Bottom up with partitioned bit strings where set=2patsizeset = 2^patsizeset=2patsize使用分区位串的自底向上法，其中 set=2patsizeset = 2^patsizeset=2patsize | General case一般情况 | O(part∗2(patsize/part)∗(rank+patno)/load)O(part \* 2^(patsize/part) \* (rank + patno) / load)O(part∗2(patsize/part)∗(rank+patno)/load) | O(subsize∗part+match)O(subsize \* part + match)O(subsize∗part+match) | O(part∗2(patsize/part)∗(rank+patno)/load)O(part \* 2^(patsize/part) \* (rank + patno) / load)O(part∗2(patsize/part)∗(rank+patno)/load) | O(subsize+part∗2(patsize/part)∗(rank+patno)+sym)O(subsize + part \* 2^(patsize/part) \* (rank + patno) + sym)O(subsize+part∗2(patsize/part)∗(rank+patno)+sym) |

Thus we may partition the set $PF$ into a fixed, chosen number $part$ of blocks $P_1, \ldots, P_part$ and represent each match set $M$ by the tuple
因此，我们可以将集合 $PF$ 划分为固定且选定数量 $part$ 的块 $P_1, \ldots, P_part$ ，并将每个匹配集 $M$ 表示为元组

$$
\langle M \cap P_1, M \cap P_2, \ldots, M \cap P_{\mathit{part}} \rangle.
$$

Then (1) and (2) of Definition 10.2 become
那么定义 10.2 中的 (1) 和 (2) 变为

$$
\begin{aligned} (1') \quad \operatorname{Match}(a) \cap P_j &= U_a \cap P_j.\\ (2') \quad \operatorname{Match}(a(t_1, \ldots, t_q)) \cap P_j &= \Bigl(U_a \cap \bigcup_{k=1}^{\mathit{part}}(\operatorname{Father}_1(\operatorname{Match}(t_1)) \cap P_k) \cap \cdots\\ &\qquad \cap \bigcup_{k=1}^{\mathit{part}}(\operatorname{Father}_q(\operatorname{Match}(t_q)) \cap P_k) \cup \{v\}\Bigr) \cap P_j. \end{aligned}
$$

For the analysis, let $set_i$ be the number of match set segments in the $i$th partition block $P_i$:
为了进行分析，令 $set_i$ 为第 $i$ 个划分块 $P_i$ 中的匹配集分段数量：

$$
\mathit{set}_i = |\{\operatorname{Match}(t) \cap P_i \mid t \in S\}|.
$$

We can then express the table size as
我们可以将表的大小表示为

$$
O\left(\frac{\mathit{set}_1 + \cdots + \mathit{set}_{\mathit{part}}}{\mathit{load}} \cdot (\mathit{rank} + \mathit{part})\right)
$$

and the matching time as $O(subsize * part + match)$.
并将匹配时间记为 $O(subsize * part + match)$ 。

For the case where $set$ is nearly $2^patsize$ and the partition sizes $|P_i|$ are each approximately equal, that is, $patsize/part$, the table size may be expressed as
对于 $set$ 接近 $2^patsize$ 且划分大小 $|P_i|$ 均近似相等（即 $patsize/part$ ）的情况，表的大小可以表示为

$$
O\left(\frac{\mathit{part}}{\mathit{load}} \cdot 2^{\mathit{patsize}/\mathit{part}} \cdot (\mathit{rank} + \mathit{patno})\right).
$$

This formula gives a good idea of the space-time trade-off involved. Given a set of patterns, the problem of choosing a good partition is as yet unexplored. Since it may lead to a clique problem (Theorem 4.3), it can perhaps only be approximated.
该公式很好地体现了其中涉及的空间与时间之间的权衡。给定一组模式，如何选择一个好的分区问题目前尚未被探讨。由于这可能会导致团问题（定理 4.3），因此或许只能得到近似解。

## 11\. Conclusions
11\. 结论

Table II summarizes the time and space complexities for the preprocessing and matching techniques we have discussed. The trade-offs are so complex that we cannot choose an all-round best method. Each of the techniques offers some strengths and has certain weaknesses.
表 II 总结了我们讨论过的预处理和匹配技术的时空复杂度。由于权衡因素非常复杂，我们无法选出一种全能的最佳方法。每种技术都有其优势，也存在某些局限性。

As in the case of sorting, users of tree-matching algorithms must choose a strategy carefully, on the basis of special properties of the patterns and subjects involved, the number of different subjects expected (and their relationship, if any) for the same set of patterns, and the available time and space resources.
与排序的情况类似，树匹配算法的使用者必须根据所涉及模式和主体的特殊属性、针对同一组模式预期处理的不同主体数量（以及它们之间的关系，如果有的话），以及可用的时间和空间资源，谨慎地选择策略。

We note that our top-down algorithm is always better than the one of Karp et al. [^18] and as good as the one of Overmars and van Leeuwen [^27], although they have a different notion of matching in mind. It is only in especially space-limited situations that the naive matching algorithm should be chosen. The version of Lang et al. [^24] might be an interesting alternative, but further experimentation seems necessary to understand better what practical advantages it has to offer.
我们注意到，我们的自顶向下算法始终优于 Karp 等人 [^18] 的算法，且与 Overmars 和 van Leeuwen [^27] 的算法一样出色，尽管他们考虑的是不同的匹配概念。只有在空间极其受限的情况下，才应选择朴素匹配算法。Lang 等人 [^24] 的版本可能是一个有趣的替代方案，但似乎有必要进行进一步的实验，以更好地了解它能提供哪些实际优势。

For the quickest matching time, the bottom-up algorithm, driven by tables, is best. We have used it in our interpreter generator and feel that for this application, the additional matching speed justifies the added preprocessing time, as long as the table size stays reasonable. Our experience with the algorithm is confirmed by the work in [^10]. When too many match sets are expected, we suggest the bit-string and hash-table methods which trade off space and time very flexibly.
为了获得最快的匹配速度，由表驱动的自底向上算法是最佳选择。我们已在解释器生成器中使用了该算法，并认为对于此类应用，只要表的大小保持在合理范围内，额外的匹配速度就足以证明增加预处理时间是值得的。我们在该算法上的经验也得到了文献 [^10] 研究工作的证实。当预期匹配集过多时，我们建议使用位串（bit-string）和哈希表方法，这些方法可以非常灵活地权衡空间和时间。

## References
参考文献

Note: References [^5][^19] are not cited in the text.
注：参考文献 [^5][^19] 未在正文中引用。

[^1]: Aho, A.V., and Corasick, M.J. Efficient string matching: An aid to bibliographic search. *Commun. ACM* 18, 6 (June 1975), 333-340.

[^2]: Aho, A.V., Hopcroft, J.E., and Ullman, J.D. *The Design and Analysis of Computer Algorithms*. Addison-Wesley, Reading, Mass., 1974.
    Aho, A.V., Hopcroft, J.E., 和 Ullman, J.D. 《计算机算法的设计与分析》(The Design and Analysis of Computer Algorithms)。Addison-Wesley，雷丁，马萨诸塞州，1974 年。

[^3]: Baxter, L.D. The complexity of unification. Ph.D. Dissertation, Dep. of Computer Science, Univ. of Waterloo, Waterloo, Ontario, Canada, 1976.
    Baxter, L.D. The complexity of unification. 博士论文, Dep. of Computer Science, Univ. of Waterloo, Waterloo, Ontario, Canada, 1976.

[^3a]: Berry, G., and Levy, J.-J. Minimal and optimal computations of recursive programs. 4th ACM Symp. on Principles of Programming Languages, Los Angeles, Calif., 1977, pp. 215-226.
    Berry, G., 以及 Levy, J.-J. Minimal and optimal computations of recursive programs. 4th ACM Symp. on Principles of Programming Languages, Los Angeles, Calif., 1977, pp. 215-226.

[^4]: Boyer, R.S., and Moore, J.S. A fast string searching algorithm. *Commun. ACM* 20, 10 (Oct. 1977), 762-772.
    Boyer, R.S., 和 Moore, J.S. 一种快速字符串搜索算法 (A fast string searching algorithm)。《ACM 通讯》(Commun. ACM) 第 20 卷，第 10 期（1977 年 10 月），762-772 页。

[^5]: Carter, J.L., and Wegman, M.N. Universal classes of hashing functions. Proc. 9th Ann. Symp. on Theory of Computing, Boulder, Colo., 1977, pp. 106-112.
    Carter, J.L., 以及 Wegman, M.N. Universal classes of hashing functions. Proc. 9th Ann. Symp. on Theory of Computing, Boulder, Colo., 1977, pp. 106-112.

[^6]: Chew, P. An improved algorithm for computing with equations. Proc. 21st IEEE Symp. on Foundations of Computer Science, Syracuse, N.Y., 1980, pp. 108-117.
    Chew, P. 一种改进的等式计算算法。第 21 届 IEEE 计算机科学基础研讨会论文集，纽约州锡拉丘兹，1980 年，第 108-117 页。

[^7]: Collins, G. The SAC-I system: An introduction and survey. Proc. 2nd ACM Conf. on Symbolic and Algebraic Manipulation, Los Angeles, Calif., 1971, pp. 144-152.
    Collins, G. SAC-I 系统：介绍与综述。第 2 届 ACM 符号与代数操作会议论文集，加利福尼亚州洛杉矶，1971 年，第 144-152 页。

[^8]: Commentz-Walter, B. A string matching algorithm fast on the average. In *Automata, Languages and Programming*, Lecture Notes in Computer Science 71, H.A. Maurer, Ed., Springer-Verlag, Berlin, Heidelberg, New York, 1979, pp. 118-132.
    Commentz-Walter, B. 一种平均速度较快的字符串匹配算法 (A string matching algorithm fast on the average)。收录于《自动机、语言和编程》(Automata, Languages and Programming)，计算机科学讲义 (Lecture Notes in Computer Science) 第 71 卷，H.A. Maurer 编，Springer-Verlag，柏林、海德堡、纽约，1979 年，118-132 页。

[^9]: Downey, P.J., Samet, H., and Sethi, R. Off-line and on-line algorithms for deducing equalities. Proc. 5th Ann. ACM Symp. on Principles of Programming Languages, Tucson, Ariz., 1978, pp. 158-170.
    Downey, P.J., Samet, H., 以及 Sethi, R. 推导等式的离线与在线算法。第 5 届 ACM 编程语言原理年度研讨会论文集，亚利桑那州图森，1978 年，第 158-170 页。

[^10]: Glasner, I., Moncke, U., and Wilhelm, R. OPTRAN, a language for the specification of program transformations. 6th GI Fachtagung uber Programmiersprachen, Darmstadt, W. Germany, 1980, to appear in Lecture Notes in Computer Science.

[^11]: Goguen, J.A. Some design principles and theory for Obj-0. Proc. Int. Conf. on Mathematical Studies of Information Processing, Kyoto, Japan, 1978, pp. 429-475.

[^12]: Guttag, J., Horowitz, E., and Musser, D. Abstract data types and software validation. ISI Rep. 76-48, Univ. of Southern California, Los Angeles, Calif., 1976.

[^13]: Guttag, J.V., Horowitz, E., and Musser, D.R. Abstract data types and software validation. *Commun. ACM* 21, 12 (Dec. 1978), 1048-1064.
    Guttag, J.V., Horowitz, E., 和 Musser, D.R. 抽象数据类型与软件验证 (Abstract data types and software validation)。《ACM 通讯》(Commun. ACM) 第 21 卷，第 12 期（1978 年 12 月），1048-1064 页。

[^14]: Hoffmann, C.M., and O'Donnell, M.J. An interpreter generator using tree pattern matching. Proc. 6th Ann. ACM Symp. on Principles of Programming Languages, San Antonio, Texas, 1979, pp. 169-179.
    Hoffmann, C.M., 和 O'Donnell, M.J. An interpreter generator using tree pattern matching. 第六届 ACM 编程语言原理年度研讨会论文集 (Proc. 6th Ann. ACM Symp. on Principles of Programming Languages), 德克萨斯州圣安东尼奥, 1979, 第 169-179 页。

[^15]: Hoffmann, C.M., and O'Donnell, M.J. Programming with equations. *ACM Trans. Prog. Lang. Syst.* 4, 1 (Jan. 1982).
    Hoffmann, C.M., 与 O'Donnell, M.J. Programming with equations. ACM Trans. Prog. Lang. Syst. 4, 1 (1982 年 1 月).

[^16]: Huet, G., and Lang, B. Proving and applying program transformations expressed with second order patterns. Tech. Rep. 266, IRIA Laboria, Le Chesnay, France, 1977.
    Huet, G., 和 Lang, B. Proving and applying program transformations expressed with second order patterns. 技术报告 266, IRIA Laboria, 法国勒谢奈, 1977。

[^17]: Huet, G., and Levy, J.-J. Call by need computations in nonambiguous linear term rewriting systems. Tech. Rep. 359, IRIA Laboria, Le Chesnay, France, 1979.
    Huet, G., 和 Levy, J.-J. Call by need computations in nonambiguous linear term rewriting systems. 技术报告 359, IRIA Laboria, 法国勒谢奈, 1979。

[^18]: Karp, R., Miller, R.E., and Rosenberg, A. Rapid identification of repeated patterns in strings, trees and arrays. Proc. 4th Ann. ACM Symp. on Theory of Computing, Denver, Colo., 1972, pp. 125-136.

[^19]: Knuth, D. *The Art of Computer Programming*, Vol. 3, Sorting and Searching. Addison-Wesley, Reading, Mass., 1973.

[^20]: Knuth, D., and Bendix, P. Simple word problems in universal algebras. In *Computational Problems in Abstract Algebra*, J. Leech, Ed., Pergamon Press, Elmsford, N.Y., 1970, pp. 263-297.
    Knuth, D., 与 Bendix, P. Simple word problems in universal algebras. 收录于 Computational Problems in Abstract Algebra, J. Leech 编, Pergamon Press, Elmsford, N.Y., 1970, 第 263-297 页.

[^21]: Knuth, D., Morris, J., and Pratt, V. Fast pattern matching in strings. *SIAM J. Comput.* 6, 2 (1977), 323-350.
    Knuth, D., Morris, J., 与 Pratt, V. Fast pattern matching in strings. SIAM J. Comput. 6, 2 (1977), 323-350.

[^22]: Kozen, D. Complexity of finitely presented algebras. Proc. 9th Ann. ACM Symp. on Theory of Computing, Boulder, Colo., 1977, pp. 164-177.

[^23]: Kron, H. Tree templates and subtree transformational grammars. Ph.D. Dissertation, Univ. of California, Santa Cruz, Calif., 1975.

[^24]: Lang, H.-W., Schimmler, M., and Schmeck, H. Matching tree patterns sublinear on the average. Tech. Rep., Dep. of Informatik, Univ. Kiel, Kiel, W. Germany, 1980.

[^25]: Nelson, G., and Oppen, D. Fast decision procedures based on congruence closure. *J. ACM* 27, 2 (April 1980), 356-364.

[^26]: O'Donnell, M.J. Computing in systems described by equations. In *Computing and Systems Described by Equations*, Lecture Notes in Computer Science 58, G. Goos and J. Hartmanis, Eds., Springer-Verlag, 1977.

[^27]: Overmars, M.H., and van Leeuwen, J. Rapid subtree identification revisited. Tech. Rep. CS-79-3, Univ. of Utrecht, Utrecht, Netherlands, 1979.

[^28]: Paterson, M.S., and Wegman, M. Linear unification. Proc. 8th ACM Symp. on Theory of Computing, Hershey, Pa., 1976, pp. 181-186.

[^29]: Robinson, J.A. A machine-oriented logic based on the resolution principle. *J. ACM* 12, 1 (Jan. 1965), 23-41.

[^30]: Rosen, B. Tree-manipulating systems and Church-Rosser theorems. *J. ACM* 20, 1 (Jan. 1973), 160-187.

[^31]: Shostak, R.E. An algorithm for reasoning about equality. *Commun. ACM* 21, 7 (July 1978), 583-585.
    Shostak, R.E. 一种关于等式推理的算法。《ACM 通讯》21, 7 (1978 年 7 月), 583-585。

[^32]: Sprugnoli, R. Perfect hashing functions: A single probe retrieving method for static sets. *Commun. ACM* 20, 11 (Nov. 1977), 841-850.
    Sprugnoli, R. 完美哈希函数：一种用于静态集的单次探测检索方法。《ACM 通讯》20, 11 (1977 年 11 月), 841-850。

[^33]: Stafford, G. Structure of the ELI compiler. Master's Thesis, Dep. of Computer Science, Univ. of Waterloo, Waterloo, Ontario, Canada, 1977.
    Stafford, G. Structure of the ELI compiler. 硕士论文, Dep. of Computer Science, Univ. of Waterloo, Waterloo, Ontario, Canada, 1977.

[^34]: Wand, M. Algebraic theories and tree rewriting systems. Tech. Rep. 66, Dep. of Computer Science, Indiana Univ., Bloomington, Ind., 1977.

Received March 1979; revised November 1980; accepted December 1980.
1979年3月收稿；1980年11月修订；1980年12月录用。
