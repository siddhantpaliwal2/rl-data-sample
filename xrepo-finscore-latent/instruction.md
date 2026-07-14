<uploaded_files>/app</uploaded_files>

The FinScore **analysis report** — the aggregated financial summary the service
builds by rolling up the upstream bank-score, spending and merchant analyses
into one customer-facing response — returns wrong numbers for certain customer
profiles, even though the project builds clean and its checks pass. The wrong
values are all in the **derived summary figures**: the "top"/"highest"/"leading"
selections the report picks out, and the ratios and share-of-income percentages
it computes. The raw pass-through fields are fine; it is the deterministic
selection-and-percentage math that is subtly off.

Two examples from support tickets:

- For a customer whose credit-card spend peaks in one month, the "highest
  credit-card utilization" figure sometimes comes back as that customer's
  *lowest* month instead of the peak.
- The "average monthly income" percentage occasionally lands an order of
  magnitude too small (e.g. a customer who should read ~60% shows ~6%).

Other summary numbers in the same report — the share of income attributed to a
customer's leading spending category, the obligation-to-income ratio, and how
many top merchants are listed — are also wrong for some inputs. The common
thread is edge inputs: an extreme value, the single largest item among several,
an exact-size set, or a figure that has to be rescaled. Away from those the
numbers are right, which is why the checks the code ships with never surface it.

This is pure, side-effect-free aggregation arithmetic — sorting, selecting the
right element, dividing by the right quantity, and scaling to a percentage.
Correct the summary math so the report is right on these edge and boundary
inputs, without changing behavior anywhere the current checks already pin. The
project's checks pass now and must stay passing; correctness on the
edge/summary inputs is the bar.

Do not add or modify anything under `src/test/`.

Verify the build with:

    cd /app && mvn -o -q test
