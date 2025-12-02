#!/usr/bin/env python3
"""
Parse perf reports - NO REGEX, just string splitting
"""

import csv
import sys
from pathlib import Path

class PerfParser:
    def __init__(self, results_dir=None):
        if results_dir:
            self.results_dir = Path(results_dir)
        else:
            results_base = Path('../results')
            matching = sorted(results_base.glob('perf-results-*'))
            if not matching:
                print("Error: No results found")
                sys.exit(1)
            self.results_dir = matching[-1]
        
        print(f"Parsing: {self.results_dir}")
        print()
    
    def parse_report(self, report_file):
        """Parse without regex - just split and look for patterns"""
        if not report_file.exists() or report_file.stat().st_size == 0:
            return []
        
        functions = []
        found_header = False
        
        with open(report_file) as f:
            for line in f:
                # Look for the header line
                if 'Children' in line and 'Self' in line and 'Symbol' in line:
                    found_header = True
                    continue
                
                if not found_header:
                    continue
                
                # Skip comment lines
                if line.strip().startswith('#'):
                    continue
                
                # Skip empty lines
                if not line.strip():
                    continue
                
                # Data lines have two percentages
                if '%' not in line:
                    continue
                
                # Split by whitespace
                parts = line.split()
                
                # We need at least: Children%, Self%, Command, Object, [.], Function
                if len(parts) < 6:
                    continue
                
                # First two parts should end with %
                if not (parts[0].endswith('%') and parts[1].endswith('%')):
                    continue
                
                try:
                    # Parse percentages
                    children = float(parts[0].rstrip('%'))
                    self_pct = float(parts[1].rstrip('%'))
                    
                    # Skip if Self is 0 (not doing actual work)
                    if self_pct == 0.0:
                        continue
                    
                    # Command is parts[2], Object is parts[3]
                    # Find the bracket (should be parts[4])
                    # Function name is everything after the bracket
                    
                    bracket_found = False
                    function_start = 0
                    
                    for i, part in enumerate(parts[4:], start=4):
                        if part.startswith('[') and part.endswith(']'):
                            bracket_found = True
                            function_start = i + 1
                            break
                    
                    if bracket_found and function_start < len(parts):
                        function = ' '.join(parts[function_start:])
                        
                        functions.append({
                            'function': function,
                            'overhead': self_pct,
                            'children': children,
                            'command': parts[2],
                            'object': parts[3]
                        })
                
                except (ValueError, IndexError) as e:
                    # Skip malformed lines
                    continue
        
        # Sort by overhead (Self %) descending
        functions.sort(key=lambda x: x['overhead'], reverse=True)
        return functions
    
    def find_versions(self):
        """Find all PostgreSQL versions"""
        versions = []
        for v in range(11, 19):
            report = self.results_dir / f'perf-pg{v}-report.txt'
            if report.exists() and report.stat().st_size > 100:  # At least 100 bytes
                versions.append(v)
        return versions
    
    def load_all_data(self, versions):
        """Load data for all versions"""
        data = {}
        
        for v in versions:
            report = self.results_dir / f'perf-pg{v}-report.txt'
            funcs = self.parse_report(report)
            
            if funcs:
                data[v] = funcs
                print(f"✓ PG{v}: {len(funcs)} functions (top: {funcs[0]['function'][:40]}... {funcs[0]['overhead']:.2f}%)")
            else:
                print(f"⚠ PG{v}: No functions with Self > 0%")
        
        print()
        return data
    
    def export_csv(self, data, versions):
        """Export to CSV"""
        output = self.results_dir / 'comparison.csv'
        
        # Collect all unique functions
        all_funcs = set()
        for funcs in data.values():
            all_funcs.update(f['function'] for f in funcs)
        
        print(f"Total unique functions: {len(all_funcs)}")
        
        # Create lookup: version -> {function: overhead}
        lookup = {}
        for v, funcs in data.items():
            lookup[v] = {f['function']: f['overhead'] for f in funcs}
        
        # Write CSV
        with open(output, 'w', newline='') as f:
            writer = csv.writer(f)
            
            # Header
            header = ['Function']
            for v in versions:
                header.append(f'PG{v} (%)')
            
            # Delta columns
            for i in range(len(versions) - 1):
                v1, v2 = versions[i], versions[i + 1]
                header.append(f'Δ {v1}→{v2}')
            
            writer.writerow(header)
            
            # Sort by latest version's overhead
            latest = versions[-1]
            sorted_funcs = sorted(
                all_funcs,
                key=lambda f: lookup[latest].get(f, 0),
                reverse=True
            )
            
            # Write rows
            for func in sorted_funcs:
                row = [func]
                
                # Overhead values
                vals = [lookup[v].get(func, 0.0) for v in versions]
                row.extend(f'{v:.2f}' for v in vals)
                
                # Deltas
                for i in range(len(vals) - 1):
                    delta = vals[i + 1] - vals[i]
                    row.append(f'{delta:+.2f}')
                
                writer.writerow(row)
        
        print(f"✓ Saved: {output}")
        return output
    
    def print_summary(self, data, versions):
        """Print top functions for each version"""
        print("=" * 80)
        print("TOP 5 FUNCTIONS BY VERSION")
        print("=" * 80)
        print()
        
        for v in versions[:3]:  # Show first 3
            if v not in data:
                continue
            
            print(f"PostgreSQL {v}:")
            for i, func in enumerate(data[v][:5], 1):
                fname = func['function'][:50]
                print(f"  {i}. {func['overhead']:6.2f}%  {fname}")
            print()
    
    def run(self):
        """Main workflow"""
        versions = self.find_versions()
        
        if not versions:
            print("No PostgreSQL versions found")
            sys.exit(1)
        
        print(f"Found versions: {versions}\n")
        
        data = self.load_all_data(versions)
        
        if not data:
            print("\nError: No data parsed")
            print("Tip: Reports need 'Self' column > 0%")
            sys.exit(1)
        
        csv_file = self.export_csv(data, versions)
        self.print_summary(data, versions)
        
        print("=" * 80)
        print("✓ Complete!")
        print()
        print(f"📊 Import to Excel: {csv_file}")

def main():
    if len(sys.argv) > 1:
        parser = PerfParser(sys.argv[1])
    else:
        parser = PerfParser()
    
    parser.run()

if __name__ == '__main__':
    main()
