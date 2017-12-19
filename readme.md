1、查看授权码是否正确
    EasyPlayer iOS授权的key是根据进程名来的
    NSString *pname = [[NSProcessInfo processInfo] processName];
    可以在工程里面执行下这一句，看下pname是多少
