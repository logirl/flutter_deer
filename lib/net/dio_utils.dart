
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_deer/util/log_utils.dart';
import 'package:flutter_deer/util/toast.dart';
import 'package:rxdart/rxdart.dart';
import '../entity_factory.dart';
import 'base_entity.dart';
import 'error_handle.dart';
import 'intercept.dart';

/// @weilu https://github.com/simplezhli
class DioUtils {

  static final DioUtils _singleton = DioUtils._internal();

  static DioUtils get instance => DioUtils();

  factory DioUtils() {
    return _singleton;
  }

  static Dio _dio;

  Dio getDio(){
    return _dio;
  }

  DioUtils._internal(){
    var options = BaseOptions(
      connectTimeout: 15000,
      receiveTimeout: 15000,
      responseType: ResponseType.plain,
      validateStatus: (status){
        // 不使用http状态码判断状态，使用AdapterInterceptor来处理（适用于标准REST风格）
        return true;
      },
      baseUrl: "https://api.github.com/",
//      contentType: ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8'),
    );
    _dio = Dio(options);
    /// 统一添加身份验证请求头
    _dio.interceptors.add(AuthInterceptor());
    /// 刷新Token
    _dio.interceptors.add(TokenInterceptor());
    /// 打印Log
    _dio.interceptors.add(LoggingInterceptor());
    /// 适配数据
    _dio.interceptors.add(AdapterInterceptor());
  }

  // 数据返回格式统一，统一处理异常
  Future<BaseEntity<T>> _request<T>(String method, String url, {Map<String, dynamic> data, Map<String, dynamic> queryParameters, CancelToken cancelToken, Options options}) async {
    var response = await _dio.request(url, data: data, queryParameters: queryParameters, options: _checkOptions(method, options), cancelToken: cancelToken);

    int _code;
    String _msg;
    T _data;

    try {
      Map<String, dynamic> _map = json.decode(response.data.toString());
      _code = _map["code"];
      _msg = _map["message"];
      if (_map.containsKey("data")){
        _data = EntityFactory.generateOBJ(_map["data"]);
      }
    }catch(e){
      print(e);
      return BaseEntity(ExceptionHandle.parse_error, "数据解析错误", _data);
    }
    return BaseEntity(_code, _msg, _data);
  }

  Future<BaseEntity<List<T>>> _requestList<T>(String method, String url, {Map<String, dynamic> data, Map<String, dynamic> queryParameters, CancelToken cancelToken, Options options}) async {
    var response = await _dio.request(url, data: data, queryParameters: queryParameters, options: _checkOptions(method, options), cancelToken: cancelToken);
    int _code;
    String _msg;
    List<T> _data = [];

    try {
      Map<String, dynamic> _map = json.decode(response.data.toString());
      _code = _map["code"];
      _msg = _map["message"];
      if (_map.containsKey("data")){
        ///  List类型处理，暂不考虑Map
        (_map["data"] as List).forEach((item){
          _data.add(EntityFactory.generateOBJ<T>(item));
        });
      }
    }catch(e){
      print(e);
      return BaseEntity(ExceptionHandle.parse_error, "数据解析错误", _data);
    }
    return BaseEntity(_code, _msg, _data);
  }

  Options _checkOptions(method, options) {
    if (options == null) {
      options = new Options();
    }
    options.method = method;
    return options;
  }

  Future<BaseEntity<T>> request<T>(Method method, String url, {Map<String, dynamic> params, Map<String, dynamic> queryParameters, CancelToken cancelToken, Options options}) async {
    try{
      String m = _getRequestMethod(method);
      return await _request<T>(m, url, data: params, queryParameters: queryParameters, options: options, cancelToken: cancelToken);
    }catch(e){
      if (e is DioError && CancelToken.isCancel(e)){
        Log.i("取消请求接口： $url");
      }
      Error error = ExceptionHandle.handleException(e);
      return Future.value(BaseEntity(error.code, error.msg, null));
    }
  }

  Future<BaseEntity<List<T>>> requestList<T>(Method method, String url, {Map<String, dynamic> params, Map<String, dynamic> queryParameters, CancelToken cancelToken, Options options}) async {
    try{
      String m = _getRequestMethod(method);
      return await _requestList<T>(m, url, data: params, queryParameters: queryParameters, options: options, cancelToken: cancelToken);
    }catch(e){
      if (e is DioError && CancelToken.isCancel(e)){
        Log.i("取消请求接口： $url");
      }
      Error error = ExceptionHandle.handleException(e);
      return Future.value(BaseEntity(error.code, error.msg, []));
    }
  }

  /// 统一处理(onSuccess返回T对象，onSuccessList返回List<T>)
  requestNetwork<T>(Method method, String url, {Function(T t) onSuccess, Function(List<T> list) onSuccessList, Function(int code, String mag) onError,
    Map<String, dynamic> params, Map<String, dynamic> queryParameters, CancelToken cancelToken, Options options, bool isList : false}){
    String m = _getRequestMethod(method);
    Observable.fromFuture(isList ? _requestList<T>(m, url, data: params, queryParameters: queryParameters, options: options, cancelToken: cancelToken) :
    _request<T>(m, url, data: params, queryParameters: queryParameters, options: options, cancelToken: cancelToken))
        .asBroadcastStream()
        .listen((result){
      if (result.code == 0){
        isList ? onSuccessList(result.data) : onSuccess(result.data);
      }else{
        onError == null ? _onError(result.code, result.message) : onError(result.code, result.message);
      }
    }, onError: (e){
      if (e is DioError && CancelToken.isCancel(e)){
        Log.i("取消请求接口： $url");
      }
      Error error = ExceptionHandle.handleException(e);
      onError == null ? _onError(error.code, error.msg) : onError(error.code, error.msg);
    });
  }

  _onError(int code, String mag){
    Log.e("接口请求异常： code: $code, mag: $mag");
    Toast.show(mag);
  }

  String _getRequestMethod(Method method){
    String m;
    switch(method){
      case Method.get:
        m = "GET";
        break;
      case Method.post:
        m = "POST";
        break;
      case Method.put:
        m = "PUT";
        break;
      case Method.patch:
        m = "PATCH";
        break;
      case Method.delete:
        m = "DELETE";
        break;
    }
    return m;
  }
}

enum Method {
  get,
  post,
  put,
  patch,
  delete,
}