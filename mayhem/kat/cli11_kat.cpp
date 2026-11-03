// Known-answer probe for the oracle: parses fixed argument vectors through the public CLI11 API
// and prints the parsed values, so mayhem/test.sh can assert exact output.
#include <CLI/CLI.hpp>
#include <iostream>
#include <string>
#include <vector>

int main() {
    CLI::App app{"kat"};
    int count{0};
    double ratio{0.0};
    std::string name;
    std::vector<int> nums;
    bool verbose{false};
    app.add_option("-c,--count", count)->check(CLI::Range(0, 100));
    app.add_option("-r,--ratio", ratio);
    app.add_option("-n,--name", name);
    app.add_option("--nums", nums)->expected(-1);
    app.add_flag("-v,--verbose", verbose);

    app.parse("-n alpha -v -r 2.5 -c 42 --nums 7 8 9");
    std::cout << "count=" << count << " ratio=" << ratio << " name=" << name << " verbose=" << verbose
              << " nums=" << nums.size() << ":" << nums[0] + nums[1] + nums[2] << "\n";

    CLI::App subapp;
    auto *sub = subapp.add_subcommand("run", "run subcommand");
    std::string target;
    sub->add_option("target", target)->required();
    subapp.parse("run build");
    std::cout << "sub=" << sub->parsed() << " target=" << target << "\n";

    bool rejected = false;
    try {
        CLI::App bad;
        int v{0};
        bad.add_option("-c", v)->check(CLI::Range(0, 100));
        bad.parse("-c 500");
    } catch(const CLI::ValidationError &) {
        rejected = true;
    }
    std::cout << "range_rejected=" << rejected << "\n";

    CLI::App cfg;
    int level{0};
    std::string tag;
    cfg.set_config("--config");
    cfg.add_option("--level", level);
    cfg.add_option("--tag", tag);
    std::stringstream in("level=13\ntag=\"hello\"\n");
    cfg.parse_from_stream(in);
    std::cout << "config level=" << level << " tag=" << tag << "\n";
    std::cout << "config_out=" << cfg.config_to_str() << "\n";
    return 0;
}
