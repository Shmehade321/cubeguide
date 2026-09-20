// Test-only process adapter. Distributed under GPL-3.0-or-later with the referenced solver.
import cs.min2phase.Search;
import java.io.BufferedReader;
import java.io.InputStreamReader;

public final class ReferenceRunner {
    public static void main(String[] args) throws Exception {
        Search.init();
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in, "UTF-8"));
        String state;
        while ((state = input.readLine()) != null) {
            String solution = new Search().solution(state, 30, 100000000L, 0L, 0);
            System.out.println(state + "\t" + solution.trim());
        }
    }
}
