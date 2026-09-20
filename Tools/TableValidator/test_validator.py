"""Literal self-checks for the independent test oracle, separate from product implementation."""
import unittest
import numpy as np
import validate

class OracleTests(unittest.TestCase):
    def test_permutation_rank_literals(self):
        values = np.array([[0,1,2,3],[0,1,3,2],[3,2,1,0]],dtype=np.uint8)
        np.testing.assert_array_equal(validate.permutation_rank(values),[0,1,23])

    def test_literal_product_graph(self):
        left=np.array([[1,2,0],[2,0,1],[0,1,2]],dtype=np.uint16)
        right=np.array([[0,0,1],[1,1,0]],dtype=np.uint16)
        np.testing.assert_array_equal(validate.recompute_distances(left,right,0),[[0,1],[1,2],[1,2]])
        np.testing.assert_array_equal(validate.recompute_distances(left,right,5),[[2,1],[2,1],[1,0]])

    def test_rejects_unreachable_graph(self):
        with self.assertRaises(ValueError):
            validate.recompute_distances(np.array([[0],[1]],dtype=np.uint16),np.array([[0]],dtype=np.uint16),0)

    def test_comparison_checks_first_middle_last_and_shape(self):
        expected=np.arange(9).reshape(3,3)
        validate.equal(expected.copy(),expected,'fixture')
        for index in [0,4,8]:
            actual=expected.copy();actual.flat[index]+=1
            with self.assertRaises(ValueError):
                validate.equal(actual,expected,'fixture')
        with self.assertRaises(ValueError):
            validate.equal(expected.reshape(1,9),expected,'fixture')

    def test_solved_slice_goal_is_not_zero(self):
        state=np.repeat(np.arange(6,dtype=np.uint8),9)[None,:]
        np.testing.assert_array_equal(validate.coordinate('sliceMove',state),[494])
        np.testing.assert_array_equal(validate.coordinate('twistMove',state),[0])
        np.testing.assert_array_equal(validate.coordinate('flipMove',state),[0])

if __name__ == '__main__':
    unittest.main()

class DistanceEdgeTests(unittest.TestCase):
    def test_legal_distances_and_bad_edge_or_predecessor(self):
        left=np.array([[1,2,0],[2,0,1],[0,1,2]],dtype=np.uint16)
        right=np.array([[0,0,1],[1,1,0]],dtype=np.uint16)
        valid=np.array([[0,1],[1,2],[1,2]],dtype=np.uint8)
        validate.check_distance_edges(valid,left,right)
        bad=valid.copy();bad[0,1]=3
        with self.assertRaises(ValueError):
            validate.check_distance_edges(bad,left,right)
        with self.assertRaises(ValueError):
            validate.check_distance_edges(np.ones_like(valid),left,right)
